"""Focused tests for the local verification entry point; no system actions."""

import contextlib
import importlib.util
import io
from pathlib import Path
import plistlib
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("verify_local", ROOT / "scripts" / "verify-local.py")
verify = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(verify)


class FakeProcess:
    def __init__(self, output="", status=0):
        self.stdout = io.StringIO(output)
        self.status = status

    def wait(self):
        return self.status


class VerifyLocalTests(unittest.TestCase):
    def test_safe_skip_pattern_matches_only_the_three_documented_suites(self):
        test_ids = [
            "InsomniaTests.UIStatusTests/testStatus",
            "InsomniaTests.UIStartupTests/testStartup",
            "InsomniaTests.KeychainStoreTests/testKeychain",
            "InsomniaTests.RecoveryScriptTests/testRestore",
        ]
        excluded, suites = verify.audit_skip_pattern(test_ids)
        self.assertEqual(len(excluded), 3)
        self.assertEqual(set(suites), verify.SKIP_SUITES)

    def test_safe_skip_pattern_fails_if_a_suite_was_renamed_or_added(self):
        with self.assertRaisesRegex(verify.VerificationError, "expected exactly"):
            verify.audit_skip_pattern(["InsomniaTests.UIStatusTests/testStatus"])

    def test_skip_pattern_detects_substring_collisions(self):
        test_ids = [
            "InsomniaTests.UIStatusTests/testStatus",
            "InsomniaTests.UIStartupTests/testStartup",
            "InsomniaTests.KeychainStoreTests/testKeychain",
            "InsomniaTests.ExtraUIStatusTests/testUnexpected",
        ]
        with self.assertRaisesRegex(verify.VerificationError, "ExtraUIStatusTests"):
            verify.audit_skip_pattern(test_ids)

    def test_swift_test_summary_records_failures_and_runtime_skips(self):
        summary = verify.parse_swift_test_summary(
            "Test Case '-[InsomniaTests.TmuxLiveRunnerTests testMissing]' skipped (tmux unavailable)\n"
            "Executed 17 tests, with 2 failures (0 unexpected) in 3.4 seconds\n"
        )
        self.assertEqual(summary["executed"], 17)
        self.assertEqual(summary["failures"], 2)
        self.assertEqual(len(summary["runtime_skips"]), 1)

    def test_python_unittest_summary_records_failures_and_skips(self):
        summary = verify.parse_unittest_summary(
            "test_one (suite.Tests.test_one) ... skipped 'fixture unavailable'\n"
            "Ran 4 tests in 0.02s\n\nFAILED (failures=1, skipped=1)\n"
        )
        self.assertEqual(summary["executed"], 4)
        self.assertEqual(summary["failures"], 1)
        self.assertEqual(summary["skipped"], 1)
        self.assertIn("fixture unavailable", summary["skipped_cases"][0])

    def test_safe_mode_requires_supported_macos_without_isolation_acknowledgment(self):
        self.assertEqual(verify.validate_mode("safe", "Darwin", "26.1", False), 26)
        with self.assertRaises(verify.UnsupportedEnvironment):
            verify.validate_mode("safe", "Linux", "26.1", False)

    def test_full_suite_requires_explicit_isolated_macos26_acknowledgment(self):
        with self.assertRaisesRegex(verify.UnsupportedEnvironment, "INSOMNIA_ISOLATED_MACOS26=1"):
            verify.validate_mode("full-isolated", "Darwin", "26.1", False)
        with self.assertRaisesRegex(verify.UnsupportedEnvironment, "requires macOS 26"):
            verify.validate_mode("full-isolated", "Darwin", "27.0", True)
        self.assertEqual(verify.validate_mode("full-isolated", "Darwin", "26.1", True), 26)

    def test_run_step_preserves_nonzero_status_and_logs_output(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "command.log"
            with contextlib.redirect_stdout(io.StringIO()):
                result = verify.run_step(
                    "fake failing command",
                    ["fake"],
                    Path(directory),
                    log,
                    runner=lambda *args, **kwargs: FakeProcess("failure detail\n", 7),
                )
            self.assertEqual(result["exit_code"], 7)
            self.assertEqual(result["status"], "fail")
            self.assertEqual(log.read_text(encoding="utf-8"), "failure detail\n")

    def test_package_check_covers_identity_and_localized_resource_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "Resources"
            locale = source / "ru.lproj"
            locale.mkdir(parents=True)
            (locale / "InfoPlist.strings").write_text('"key" = "value";\n', encoding="utf-8")
            info = {
                "CFBundleIdentifier": verify.EXPECTED_BUNDLE_ID,
                "CFBundleExecutable": "Insomnia",
                "CFBundleShortVersionString": "0.1.0",
                "CFBundleVersion": "1",
            }
            with (source / "Info.plist").open("wb") as output:
                plistlib.dump(info, output)
            app = root / "package" / "Insomnia.app"
            contents = app / "Contents"
            (contents / "MacOS").mkdir(parents=True)
            resources = contents / "Resources"
            resources.mkdir()
            with (contents / "Info.plist").open("wb") as output:
                plistlib.dump(info, output)
            executable = contents / "MacOS" / "Insomnia"
            executable.write_text("fake executable", encoding="utf-8")
            executable.chmod(0o755)
            (resources / "AppIcon.icns").write_bytes(b"icon")
            (resources / "backstop.sh").write_text("#!/bin/bash\n", encoding="utf-8")
            packaged_locale = resources / "ru.lproj"
            packaged_locale.mkdir()
            (packaged_locale / "InfoPlist.strings").write_text('"key" = "value";\n', encoding="utf-8")
            bin_path = root / "bin"
            bin_path.mkdir()

            result = verify.verify_package(root, app, bin_path)

            self.assertEqual(result["bundle_identifier"], verify.EXPECTED_BUNDLE_ID)
            self.assertEqual(result["localized_info_plists"], ["Resources/ru.lproj/InfoPlist.strings"])

    def test_package_check_rejects_missing_localized_resources(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "Resources"
            locale = source / "ru.lproj"
            locale.mkdir(parents=True)
            (locale / "InfoPlist.strings").write_text('"key" = "source";\n', encoding="utf-8")
            info = {
                "CFBundleIdentifier": verify.EXPECTED_BUNDLE_ID,
                "CFBundleShortVersionString": "0.1.0",
                "CFBundleVersion": "1",
            }
            with (source / "Info.plist").open("wb") as output:
                plistlib.dump(info, output)
            app = root / "package" / "Insomnia.app"
            contents = app / "Contents"
            (contents / "MacOS").mkdir(parents=True)
            resources = contents / "Resources"
            resources.mkdir()
            with (contents / "Info.plist").open("wb") as output:
                plistlib.dump(info, output)
            executable = contents / "MacOS" / "Insomnia"
            executable.write_text("fake", encoding="utf-8")
            executable.chmod(0o755)
            (resources / "AppIcon.icns").write_bytes(b"icon")
            (resources / "backstop.sh").write_text("#!/bin/bash\n", encoding="utf-8")
            bin_path = root / "bin"
            bin_path.mkdir()

            with self.assertRaisesRegex(verify.VerificationError, "localized Info.plist"):
                verify.verify_package(root, app, bin_path)


if __name__ == "__main__":
    unittest.main()
