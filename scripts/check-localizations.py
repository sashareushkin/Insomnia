#!/usr/bin/env python3
"""Check localization key parity, format placeholders, plural forms and source references."""

from __future__ import annotations

import ast
import json
import plistlib
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
LOCALES = ("en", "ru")
STRING_LINE = re.compile(r'^("(?:\\.|[^"\\])*")\s*=\s*("(?:\\.|[^"\\])*");$')
REFERENCE = re.compile(r'\bL10n\.(?:string|format|plural)\s*\(\s*("(?:\\.|[^"\\])*")')
FORMAT_TOKEN = re.compile(r"%(?:[0-9]+\$)?[-+ #0]*\d*(?:\.\d+)?[hlLzjt]*([@diuoxXfFeEgGcsp%])")


def strings_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = line.strip()
        if not line or line.startswith(("//", "/*", "*")):
            continue
        match = STRING_LINE.fullmatch(line)
        if not match:
            raise ValueError(f"{path}:{number}: invalid .strings entry")
        key, value = (json.loads(part) for part in match.groups())
        if key in values:
            raise ValueError(f"{path}:{number}: duplicate key {key!r}")
        values[key] = value
    return values


def swift_string(literal: str) -> str:
    literal = re.sub(r"\\u\{([0-9A-Fa-f]+)\}", lambda m: f"\\U{int(m.group(1), 16):08x}", literal)
    return ast.literal_eval(literal)


def signatures(text: str) -> list[str]:
    return FORMAT_TOKEN.findall(text)


def main() -> int:
    errors: list[str] = []
    catalogs = {
        locale: strings_file(ROOT / "Sources/Insomnia/Resources" / f"{locale}.lproj/Localizable.strings")
        for locale in LOCALES
    }
    base_keys = set(catalogs["en"])
    for locale, catalog in catalogs.items():
        if set(catalog) != base_keys:
            errors.append(f"{locale}: Localizable.strings keys differ from en")
        for key in base_keys & set(catalog):
            if signatures(key) != signatures(catalog[key]):
                errors.append(f"{locale}: format placeholders differ for {key!r}")

    plist_keys = {}
    for locale in LOCALES:
        path = ROOT / "Resources" / f"{locale}.lproj/InfoPlist.strings"
        plist_keys[locale] = strings_file(path)
    if set(plist_keys["en"]) != set(plist_keys["ru"]):
        errors.append("InfoPlist.strings keys differ between en and ru")
    for key in set(plist_keys["en"]) & set(plist_keys["ru"]):
        if signatures(plist_keys["en"][key]) != signatures(plist_keys["ru"][key]):
            errors.append(f"InfoPlist.strings format placeholders differ for {key!r}")

    plural_catalogs = {}
    plural_keys = set()
    required_plurals = {"minutes", "hours", "days", "appsFrozen"}
    for locale in LOCALES:
        path = ROOT / "Sources/Insomnia/Resources" / f"{locale}.lproj/Localizable.stringsdict"
        with path.open("rb") as handle:
            plural_catalogs[locale] = plistlib.load(handle)
        plural_keys = set(plural_catalogs[locale])
        if locale == "ru":
            for key in required_plurals:
                forms = plural_catalogs[locale].get(key, {}).get("count", {})
                missing = {"one", "few", "many", "other"} - set(forms)
                if missing:
                    errors.append(f"ru stringsdict {key}: missing plural forms {sorted(missing)}")
    if set(plural_catalogs["en"]) != set(plural_catalogs["ru"]):
        errors.append("Localizable.stringsdict keys differ between en and ru")
    for key in set(plural_catalogs["en"]) & set(plural_catalogs["ru"]):
        en_forms = plural_catalogs["en"][key]["count"]
        ru_forms = plural_catalogs["ru"][key]["count"]
        for category in set(en_forms) & set(ru_forms):
            if category in {"one", "few", "many", "other"} and signatures(en_forms[category]) != signatures(ru_forms[category]):
                errors.append(f"stringsdict {key}/{category}: format placeholders differ")

    referenced: set[str] = set()
    for source in (ROOT / "Sources/Insomnia").rglob("*.swift"):
        for match in REFERENCE.finditer(source.read_text(encoding="utf-8")):
            referenced.add(swift_string(match.group(1)))
    available = base_keys | plural_keys
    for key in sorted(referenced - available):
        errors.append(f"{key!r}: referenced by Swift but missing from localization resources")

    info = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())
    if info.get("CFBundleDevelopmentRegion") != "en" or set(info.get("CFBundleLocalizations", [])) != set(LOCALES):
        errors.append("Info.plist must declare en as the development region and both en/ru localizations")

    if errors:
        print("Localization check failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    print(f"Localization check passed: {len(base_keys)} strings, {len(plural_keys)} plural keys, en/ru parity.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
