#!/usr/bin/env python3
"""Verify a proposed Insomnia change locally without changing the checkout.

All checks run in a temporary worktree containing the merge of the selected
candidate into the latest fetched origin/custom. Reports, logs, the temporary
app bundle, and SwiftPM build products live outside the source checkout.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import time
from typing import Any, Callable


SKIP_PATTERN = "UIStatusTests|UIStartupTests|KeychainStoreTests"
SKIP_SUITES = {"UIStatusTests", "UIStartupTests", "KeychainStoreTests"}
EXPECTED_BUNDLE_ID = "com.kgarg.insomnia"


class VerificationError(RuntimeError):
    """A verification precondition or check failed."""


class UnsupportedEnvironment(VerificationError):
    """The requested checks cannot safely run on this host."""


def run_capture(command: list[str], cwd: Path, env: dict[str, str] | None = None) -> str:
    result = subprocess.run(command, cwd=cwd, env=env, text=True, capture_output=True)
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip() or f"exit {result.returncode}"
        raise VerificationError(f"{command[0]} failed: {detail}")
    return result.stdout.strip()


def run_step(
    label: str,
    command: list[str],
    cwd: Path,
    log_path: Path,
    env: dict[str, str] | None = None,
    runner: Callable[..., subprocess.Popen[str]] = subprocess.Popen,
    stream_output: bool = True,
) -> dict[str, Any]:
    """Run and stream one command, preserving its exit code and full output."""
    started = time.monotonic()
    merged_env = os.environ.copy()
    if env:
        merged_env.update(env)
    process = runner(
        command,
        cwd=cwd,
        env=merged_env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    output: list[str] = []
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("w", encoding="utf-8") as log:
        assert process.stdout is not None
        for line in process.stdout:
            output.append(line)
            log.write(line)
            log.flush()
            if stream_output:
                sys.stdout.write(line)
                sys.stdout.flush()
        return_code = process.wait()
    result = {
        "label": label,
        "command": command,
        "exit_code": return_code,
        "status": "pass" if return_code == 0 else "fail",
        "duration_seconds": round(time.monotonic() - started, 3),
        "log": str(log_path),
        "output": "".join(output),
    }
    return result


def parse_test_inventory(output: str) -> list[str]:
    return [line.strip() for line in output.splitlines() if line.startswith("InsomniaTests.") and "/" in line]


def suite_for(test_identifier: str) -> str | None:
    match = re.match(r"^[^.]+\.([^/]+)/", test_identifier)
    return match.group(1) if match else None


def audit_skip_pattern(test_identifiers: list[str]) -> tuple[list[str], dict[str, int]]:
    matches = [test for test in test_identifiers if re.search(SKIP_PATTERN, test)]
    suites: dict[str, int] = {}
    for test in matches:
        suite = suite_for(test)
        if suite:
            suites[suite] = suites.get(suite, 0) + 1
    found = set(suites)
    if found != SKIP_SUITES:
        expected = ", ".join(sorted(SKIP_SUITES))
        actual = ", ".join(sorted(found)) or "none"
        raise VerificationError(f"test skip pattern matched suites [{actual}], expected exactly [{expected}]")
    return matches, suites


def parse_swift_test_summary(output: str) -> dict[str, Any]:
    summaries = re.findall(r"Executed (\d+) tests?, with (\d+) failures?", output)
    if not summaries:
        raise VerificationError("swift test exited successfully without an XCTest execution summary")
    executed, failures = map(int, summaries[-1])
    runtime_skips = re.findall(r"Test Case '([^']+)' skipped(?:\s|\()", output)
    return {
        "executed": executed,
        "failures": failures,
        "runtime_skips": runtime_skips,
    }


def parse_unittest_summary(output: str) -> dict[str, Any]:
    matches = re.findall(r"Ran (\d+) tests? in [^\n]+", output)
    if not matches:
        raise VerificationError("Python unittest exited without a test summary")
    result_lines = re.findall(r"^(OK|FAILED)(?: \(([^)]*)\))?\s*$", output, re.MULTILINE)
    if not result_lines:
        raise VerificationError("Python unittest output has no final result")
    result, details = result_lines[-1]
    counts = {name: 0 for name in ("failures", "errors", "skipped")}
    if details:
        for name, count in re.findall(r"(failures|errors|skipped)=(\d+)", details):
            counts[name] = int(count)
    skipped_cases = [line.strip() for line in output.splitlines() if " skipped " in line]
    return {"executed": int(matches[-1]), "result": result, **counts, "skipped_cases": skipped_cases}


def validate_mode(mode: str, system: str, macos_version: str, isolated_acknowledged: bool) -> int:
    match = re.match(r"^(\d+)", macos_version)
    major = int(match.group(1)) if match else 0
    if system != "Darwin" or major < 26:
        raise UnsupportedEnvironment("local verification requires macOS 26 or newer with Xcode and SwiftPM")
    if mode == "full-isolated":
        if major != 26:
            raise UnsupportedEnvironment("full-isolated mode requires macOS 26")
        if not isolated_acknowledged:
            raise UnsupportedEnvironment(
                "full-isolated mode requires INSOMNIA_ISOLATED_MACOS26=1 after confirming this is a "
                "disposable macOS 26 VM or dedicated test Mac"
            )
    return major


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def verify_package(
    repo: Path,
    app: Path,
    bin_path: Path,
) -> dict[str, Any]:
    info = app / "Contents" / "Info.plist"
    executable = app / "Contents" / "MacOS" / "Insomnia"
    resources = app / "Contents" / "Resources"
    if not info.is_file() or not executable.is_file() or not os.access(executable, os.X_OK):
        raise VerificationError("temporary Insomnia.app is missing its plist or executable")

    with (repo / "Resources" / "Info.plist").open("rb") as source:
        expected_info = plistlib.load(source)
    with info.open("rb") as packaged:
        actual_info = plistlib.load(packaged)
    if actual_info != expected_info:
        raise VerificationError("temporary app Info.plist does not match Resources/Info.plist")
    if actual_info.get("CFBundleIdentifier") != EXPECTED_BUNDLE_ID:
        raise VerificationError(
            f"unexpected bundle identifier {actual_info.get('CFBundleIdentifier')!r}; "
            f"expected {EXPECTED_BUNDLE_ID}"
        )
    if not actual_info.get("CFBundleShortVersionString") or not actual_info.get("CFBundleVersion"):
        raise VerificationError("temporary app is missing its expected version or build number")

    required_resources = [resources / "AppIcon.icns", resources / "backstop.sh"]
    missing = [str(path.relative_to(app)) for path in required_resources if not path.is_file()]
    if missing:
        raise VerificationError(f"temporary app is missing resources: {', '.join(missing)}")

    localized_info = sorted((repo / "Resources").glob("*.lproj/InfoPlist.strings"))
    for source in localized_info:
        relative = source.relative_to(repo / "Resources")
        destination = resources / relative
        if not destination.is_file() or sha256(source) != sha256(destination):
            raise VerificationError(f"localized Info.plist resource was not packaged faithfully: {relative}")

    package_bundle = bin_path / "Insomnia_Insomnia.bundle"
    source_resource_dirs = sorted((repo / "Sources" / "Insomnia" / "Resources").glob("*.lproj"))
    if source_resource_dirs and not package_bundle.is_dir():
        raise VerificationError("localized SwiftPM sources exist but the release resource bundle is missing")
    if package_bundle.exists():
        app_bundle = resources / package_bundle.name
        if not app_bundle.is_dir():
            raise VerificationError(f"temporary app is missing SwiftPM resources: {package_bundle.name}")
        expected_files = {item.relative_to(package_bundle) for item in package_bundle.rglob("*") if item.is_file()}
        actual_files = {item.relative_to(app_bundle) for item in app_bundle.rglob("*") if item.is_file()}
        if expected_files != actual_files:
            raise VerificationError(f"packaged SwiftPM resource files differ: {package_bundle.name}")
        for relative in expected_files:
            if sha256(package_bundle / relative) != sha256(app_bundle / relative):
                raise VerificationError(f"packaged SwiftPM resource differs: {package_bundle.name}/{relative}")

    return {
        "app_path": str(app),
        "bundle_identifier": actual_info["CFBundleIdentifier"],
        "version": actual_info["CFBundleShortVersionString"],
        "build_number": actual_info["CFBundleVersion"],
        "localized_info_plists": [str(path.relative_to(repo)) for path in localized_info],
        "swiftpm_resource_bundle": package_bundle.name if package_bundle.exists() else None,
        "signature_command": ["/usr/bin/codesign", "--verify", "--strict", str(app)],
    }


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build, test, package, and report the latest local merge candidate for Insomnia."
    )
    parser.add_argument("mode", choices=("safe", "full-isolated"), nargs="?", default="safe")
    parser.add_argument("--candidate", default="HEAD", help="candidate commit/ref; defaults to HEAD")
    parser.add_argument("--base", default="origin/custom", help="merge base; defaults to origin/custom")
    parser.add_argument("--report-dir", help="new report directory outside the checkout")
    return parser.parse_args(argv)


def markdown_report(report: dict[str, Any]) -> str:
    metadata = report["metadata"]
    rows = [
        "# Insomnia local verification",
        "",
        f"**Result: {report['result']}**",
        "",
        f"- Date (UTC): {metadata.get('date_utc', 'unknown')}",
        f"- Mode: `{report['mode']}`",
        f"- Checkout branch: `{metadata.get('branch') or '(detached)'}`",
        f"- Checkout HEAD: `{metadata.get('checkout_head_sha', 'unknown')}`",
        f"- Candidate commit: `{metadata.get('candidate_sha', 'unknown')}`",
        f"- Tested HEAD SHA: `{metadata.get('tested_head_sha', 'unknown')}`",
        f"- Base commit: `{metadata.get('base_sha', 'unknown')}`",
        f"- `origin/main` mirror SHA: `{metadata.get('origin_main_sha') or 'unavailable'}`",
        f"- Tested merge tree: `{metadata.get('merge_tree_sha', 'unknown')}`",
        f"- Dirty source checkout: `{metadata.get('dirty', 'unknown')}`",
        f"- macOS: `{metadata.get('macos', 'unknown')}` ({metadata.get('macos_build', 'unknown')})",
        f"- Xcode: `{metadata.get('xcode', 'unknown')}`",
        f"- Swift: `{metadata.get('swift', 'unknown')}`",
        f"- Architecture: `{metadata.get('architecture', 'unknown')}`",
        "",
        "## Checks",
        "",
        "| Check | Result | Duration | Log | Reason |",
        "| --- | --- | ---: | --- | --- |",
    ]
    for step in report["steps"]:
        log = Path(step["log"]).name if step.get("log") else ""
        rows.append(
            f"| {step['label']} | {step['status'].upper()} | "
            f"{step.get('duration_seconds', 0):.1f}s | `{log}` | {step.get('reason', '')} |"
        )
    tests = report.get("tests")
    rows.extend(["", "## Test totals", ""])
    for suite in report.get("python_tests", []):
        rows.append(
            f"- {suite['label']}: {suite['executed']} tests, {suite['failures']} failures, "
            f"{suite['errors']} errors, {suite['skipped']} skipped"
        )
        if suite.get("skipped_cases"):
            rows.extend([f"  Skipped in {suite['label']}:", *[f"  - `{item}`" for item in suite["skipped_cases"]]])
    if tests:
        rows.extend(
            [
                f"- Listed: {tests.get('listed', 'unknown')}",
                f"- Excluded test cases: {len(tests.get('excluded', []))}",
                f"- Executed: {tests.get('executed', 'unknown')}",
                f"- Failures: {tests.get('failures', 'unknown')}",
                f"- Runtime skips: {len(tests.get('runtime_skips', []))}",
            ]
        )
        if tests.get("excluded"):
            rows.extend(
                [
                    "",
                    f"Excluded by safe-mode policy (`{SKIP_PATTERN}`):",
                    *[f"- `{item}`" for item in tests["excluded"]],
                ]
            )
        if tests.get("runtime_skips"):
            rows.extend(["", "Runtime skips:", *[f"- `{item}`" for item in tests["runtime_skips"]]])
    else:
        rows.append("Test execution did not complete.")
    rows.extend(["", "## Packaging", ""])
    package = report.get("package")
    if package:
        rows.extend(
            [
                f"- Temporary app: `{package['app_path']}`",
                f"- Bundle ID: `{package['bundle_identifier']}`",
                f"- Version/build: `{package['version']}` / `{package['build_number']}`",
                f"- Code signature: verified with `codesign --verify --strict`",
            ]
        )
    else:
        rows.append("Packaging did not complete.")
    if report.get("error"):
        rows.extend(["", "## Stopped", "", report["error"]])
    rows.extend(
        [
            "",
            "This report is local evidence for the listed candidate/base/tree only. "
            "It does not post or forge a GitHub status check.",
            "",
        ]
    )
    return "\n".join(rows)


def write_report(report: dict[str, Any], report_dir: Path) -> None:
    report["result"] = report.get("result", "INCOMPLETE")
    (report_dir / "verification.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    (report_dir / "verification.md").write_text(markdown_report(report), encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv if argv is not None else sys.argv[1:])
    script_root = Path(__file__).resolve().parent.parent
    repo = Path(run_capture(["git", "rev-parse", "--show-toplevel"], script_root))
    if repo != script_root:
        raise VerificationError(f"verification script must be inside the repository root ({repo})")

    now = datetime.now(timezone.utc)
    if args.report_dir:
        report_dir = Path(args.report_dir).expanduser().resolve()
    else:
        report_dir = Path(tempfile.gettempdir()) / "insomnia-verification" / now.strftime("%Y%m%dT%H%M%S%fZ")
    try:
        report_dir.relative_to(repo)
    except ValueError:
        pass
    else:
        raise VerificationError("report directory must be outside the source checkout")
    report_dir.mkdir(parents=True, exist_ok=False)
    logs = report_dir / "logs"
    logs.mkdir()

    report: dict[str, Any] = {
        "schema_version": 1,
        "mode": args.mode,
        "result": "INCOMPLETE",
        "metadata": {"date_utc": now.isoformat(), "candidate_ref": args.candidate, "base_ref": args.base},
        "steps": [],
        "python_tests": [],
        "tests": None,
        "package": None,
        "error": None,
    }
    worktree_parent: Path | None = None
    worktree: Path | None = None
    exit_code = 1

    def step(
        label: str,
        command: list[str],
        cwd: Path,
        env: dict[str, str] | None = None,
        check: bool = True,
        stream_output: bool = True,
    ) -> dict[str, Any]:
        filename = re.sub(r"[^A-Za-z0-9._-]+", "-", label).strip("-") or "step"
        result = run_step(
            label,
            command,
            cwd,
            logs / f"{len(report['steps']) + 1:02d}-{filename}.log",
            env=env,
            stream_output=stream_output,
        )
        report["steps"].append({key: value for key, value in result.items() if key != "output"})
        if check and result["exit_code"] != 0:
            raise VerificationError(f"{label} failed with exit status {result['exit_code']}; see {result['log']}")
        return result

    try:
        metadata = report["metadata"]
        metadata["repository_path"] = str(repo)
        metadata["branch"] = run_capture(["git", "branch", "--show-current"], repo) or None
        metadata["checkout_head_sha"] = run_capture(["git", "rev-parse", "HEAD"], repo)
        metadata["dirty"] = bool(run_capture(["git", "status", "--porcelain", "--untracked-files=all"], repo))
        if metadata["dirty"]:
            raise VerificationError("source checkout is dirty; commit or stash changes before verification")
        metadata["architecture"] = platform.machine()
        metadata["python"] = platform.python_version()
        metadata["macos"] = run_capture(["/usr/bin/sw_vers", "-productVersion"], repo)
        metadata["macos_build"] = run_capture(["/usr/bin/sw_vers", "-buildVersion"], repo)
        metadata["xcode"] = run_capture(["/usr/bin/xcodebuild", "-version"], repo).replace("\n", ", ")
        metadata["swift"] = run_capture(["swift", "--version"], repo).splitlines()[0]
        metadata["origin"] = run_capture(["git", "remote", "get-url", "origin"], repo)

        validate_mode(
            args.mode,
            platform.system(),
            metadata["macos"],
            os.environ.get("INSOMNIA_ISOLATED_MACOS26") == "1",
        )

        step("Fetch origin refs", ["git", "fetch", "origin"], repo)
        base_sha = run_capture(["git", "rev-parse", f"{args.base}^{{commit}}"], repo)
        candidate_sha = run_capture(["git", "rev-parse", f"{args.candidate}^{{commit}}"], repo)
        try:
            metadata["origin_main_sha"] = run_capture(["git", "rev-parse", "origin/main^{commit}"], repo)
        except VerificationError:
            metadata["origin_main_sha"] = None
        metadata["base_sha"] = base_sha
        metadata["candidate_sha"] = candidate_sha
        metadata["tested_head_sha"] = candidate_sha

        worktree_parent = Path(tempfile.mkdtemp(prefix="insomnia-verification-"))
        worktree = worktree_parent / "checkout"
        step("Create temporary verification worktree", ["git", "worktree", "add", "--detach", str(worktree), base_sha], repo)
        merge_result = step(
            "Merge candidate into latest base",
            ["git", "merge", "--no-commit", "--no-ff", "--no-edit", candidate_sha],
            worktree,
            check=False,
        )
        if merge_result["exit_code"] != 0:
            raise VerificationError("candidate cannot be merged into the selected base; resolve conflicts first")
        metadata["merge_tree_sha"] = run_capture(["git", "write-tree"], worktree)

        step("Check whitespace errors", ["git", "diff", "--check", base_sha], worktree)
        python_test_suites = [
            (
                "Test upstream synchronization unit suite",
                ["python3", "-m", "unittest", "discover", "-s", ".github/scripts", "-p", "test_upstream_sync.py", "-v"],
            )
        ]
        verifier_tests = worktree / ".github" / "scripts" / "test_verify_local.py"
        if verifier_tests.is_file():
            python_test_suites.append(
                (
                    "Test local verifier unit suite",
                    ["python3", "-m", "unittest", "discover", "-s", ".github/scripts", "-p", "test_verify_local.py", "-v"],
                )
            )
        else:
            report["steps"].append(
                {"label": "Test local verifier unit suite", "status": "skip", "reason": "test suite is not present in candidate"}
            )
        for label, command in python_test_suites:
            result = step(label, command, worktree, check=False)
            summary = parse_unittest_summary(result["output"])
            summary["label"] = label
            report["python_tests"].append(summary)
            if result["exit_code"] != 0 or summary["result"] != "OK":
                raise VerificationError(f"{label} failed; see {result['log']}")

        localization_checker = worktree / "scripts" / "check-localizations.py"
        if localization_checker.is_file():
            step("Validate localization catalogs", ["python3", "scripts/check-localizations.py"], worktree)
        else:
            source_locales = list((worktree / "Sources" / "Insomnia" / "Resources").glob("*.lproj"))
            if source_locales:
                raise VerificationError("localized SwiftPM resources exist but scripts/check-localizations.py is missing")
            report["steps"].append(
                {"label": "Validate localization catalogs", "status": "skip", "reason": "checker is not present in candidate"}
            )

        shell_scripts = sorted((worktree / "scripts").glob("*.sh")) + sorted(
            (worktree / ".github" / "scripts").glob("*.sh")
        )
        for shell_script in shell_scripts:
            relative = shell_script.relative_to(worktree).as_posix()
            step(f"Bash syntax: {relative}", ["/bin/bash", "-n", relative], worktree)

        plist_files = [worktree / "Resources" / "Info.plist"] + sorted(
            (worktree / "Resources").glob("*.lproj/InfoPlist.strings")
        )
        for plist in plist_files:
            relative = plist.relative_to(worktree).as_posix()
            step(f"Lint plist: {relative}", ["/usr/bin/plutil", "-lint", relative], worktree)

        step("Build debug configuration", ["swift", "build"], worktree)
        step(
            "Check lid simulation release gate",
            ["scripts/check-lid-simulation-gate.sh"],
            worktree,
        )

        package_out = report_dir / "package"
        step(
            "Build temporary app bundle",
            ["scripts/build-app.sh", "--output", str(package_out)],
            worktree,
            {"INSOMNIA_LID_SIMULATION": ""},
        )
        app = package_out / "Insomnia.app"
        bin_result = step("Locate release binary resources", ["swift", "build", "-c", "release", "--show-bin-path"], worktree)
        bin_path = Path(bin_result["output"].splitlines()[-1].strip())
        report["package"] = verify_package(worktree, app, bin_path)
        step("Verify temporary app signature", ["/usr/bin/codesign", "--verify", "--strict", str(app)], worktree)

        inventory_result = step("List Swift tests", ["swift", "test", "list"], worktree, stream_output=False)
        inventory = parse_test_inventory(inventory_result["output"])
        if not inventory:
            raise VerificationError("swift test list returned no Insomnia XCTest cases")
        if args.mode == "safe":
            excluded, excluded_counts = audit_skip_pattern(inventory)
            test_command = ["swift", "test", "--skip", SKIP_PATTERN]
            excluded_suites = sorted(excluded_counts)
        else:
            excluded = []
            excluded_suites = []
            test_command = ["swift", "test"]
        expected_count = len(inventory) - len(excluded)
        print(
            f"Swift test inventory: {len(inventory)} test cases; "
            f"{len(excluded)} excluded by mode; {expected_count} selected."
        )
        test_result = step(
            "Run Swift tests", test_command, worktree, {"NSUnbufferedIO": "YES"}, check=False
        )
        summary = parse_swift_test_summary(test_result["output"])
        summary.update(
            {
                "listed": len(inventory),
                "expected_executed": expected_count,
                "excluded": excluded,
                "excluded_suites": excluded_suites,
            }
        )
        report["tests"] = summary
        if summary["executed"] != expected_count:
            raise VerificationError(
                f"Swift ran {summary['executed']} test cases; the discovered suite and selected mode require "
                f"{expected_count} (listed {len(inventory)}, excluded {len(excluded)})"
            )
        if test_result["exit_code"] != 0 or summary["failures"]:
            raise VerificationError(f"Swift tests reported {summary['failures']} failure(s)")

        report["result"] = "PASS"
        exit_code = 0
    except UnsupportedEnvironment as error:
        report["result"] = "INCOMPLETE"
        report["error"] = str(error)
    except (VerificationError, OSError, subprocess.SubprocessError) as error:
        report["result"] = "FAIL"
        report["error"] = str(error)
    finally:
        if worktree and worktree.exists():
            subprocess.run(["git", "worktree", "remove", "--force", str(worktree)], cwd=repo, text=True, capture_output=True)
        if worktree_parent:
            shutil.rmtree(worktree_parent, ignore_errors=True)
        write_report(report, report_dir)

    print(f"Local verification: {report['result']}")
    print(f"Report: {report_dir / 'verification.md'}")
    print(f"Machine-readable report: {report_dir / 'verification.json'}")
    return exit_code


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except VerificationError as error:
        print(f"verify-local: {error}", file=sys.stderr)
        raise SystemExit(2)
