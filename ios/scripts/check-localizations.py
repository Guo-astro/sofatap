#!/usr/bin/env python3
"""Check native locale completeness without requiring Xcode or network access."""

from collections import Counter
import json
from pathlib import Path
import re
import subprocess
import sys


APP = Path(__file__).resolve().parents[1] / "SofaTap"
# Mirrors chekusu/sofatap.app scripts/locales.mjs at bb3ee731c3ef5240d354bad7e1722d9cf7bdb496.
# Website zh-CN maps to Apple's script-based Simplified Chinese identifier.
LOCALES = {"en", "zh-Hans", "es", "fr", "de", "pt-BR", "ja", "ko", "ar", "hi", "ru", "id"}
TABLES = ("Localizable.strings", "InfoPlist.strings")
ENTRY = re.compile(r'("(?:\\.|[^"\\])*")\s*=\s*("(?:\\.|[^"\\])*")\s*;')
COMMENTS = re.compile(r"/\*.*?\*/", re.S)
FORMAT = re.compile(r"%%|%(?:(\d+)\$)?[-+ #0]*(?:\d+|\*)?(?:\.(?:\d+|\*))?(hh|h|ll|l|q|L|z|t|j)?([@diouxXeEfFgGaAcCsSp])")
HAN = re.compile(r"[\u3400-\u9fff]")
LOCALIZED_CALL = re.compile(r'(?:String\(localized:|NSLocalizedString\(|localized\()\s*"((?:\\.|[^"\\])*)"')


def read_strings(path: Path, errors: list[str]) -> dict[str, str]:
    if not path.exists():
        errors.append(f"Missing {path.relative_to(APP)}")
        return {}
    source = path.read_text(encoding="utf-8")
    values: dict[str, str] = {}
    remainder: list[str] = []
    end = 0
    for match in ENTRY.finditer(source):
        remainder.append(source[end:match.start()])
        end = match.end()
        key, value = map(json.loads, match.groups())
        if key in values:
            errors.append(f"{path.relative_to(APP)}: duplicate {key!r}")
        if not value.strip():
            errors.append(f"{path.relative_to(APP)}: empty {key!r}")
        values[key] = value
    remainder.append(source[end:])
    if COMMENTS.sub("", "".join(remainder)).strip():
        errors.append(f"{path.relative_to(APP)}: unparsed .strings content")
    # Apple's parser independently validates the files on macOS. The checks above
    # keep this useful on Linux CI too.
    if sys.platform == "darwin":
        result = subprocess.run(["plutil", "-lint", str(path)], capture_output=True, text=True)
        if result.returncode:
            errors.append(result.stdout.strip() or result.stderr.strip())
    return values


def placeholders(value: str) -> Counter:
    """Keep argument positions and multiplicity, including reordered placeholders."""
    result: Counter = Counter()
    implicit_position = 0
    for match in FORMAT.finditer(value):
        if match.group(0) == "%%":
            continue
        position, length, kind = match.groups()
        if position is None:
            implicit_position += 1
            position = str(implicit_position)
        result[(int(position), (length or "") + kind)] += 1
    return result


def main() -> int:
    errors: list[str] = []
    found = {path.stem for path in APP.glob("*.lproj") if path.is_dir()}
    if found != LOCALES:
        errors.append(f"Locale set mismatch: missing={sorted(LOCALES - found)}, extra={sorted(found - LOCALES)}")
    tables = {(locale, name): read_strings(APP / f"{locale}.lproj" / name, errors)
              for locale in sorted(LOCALES) for name in TABLES}
    for (locale, name), values in tables.items():
        english = tables[("en", name)]
        missing, extra = english.keys() - values.keys(), values.keys() - english.keys()
        if missing or extra:
            errors.append(f"{locale}/{name}: missing={sorted(missing)}, extra={sorted(extra)}")
        for key, value in values.items():
            if key in english and placeholders(value) != placeholders(english[key]):
                errors.append(f"{locale}/{name}: format arguments differ for {key!r}")
            if locale not in {"zh-Hans", "ja"} and HAN.search(value):
                errors.append(f"{locale}/{name}: untranslated Han characters in {key!r}")
            if "Sofa Tap" in value or "SofaTap" in value:
                errors.append(f"{locale}/{name}: incorrect public brand in {key!r}")
    english = tables[("en", "Localizable.strings")]
    for path in APP.rglob("*.swift"):
        for match in LOCALIZED_CALL.finditer(path.read_text(encoding="utf-8")):
            raw_key = match.group(1)
            # Swift interpolation generates typed format arguments. Those existing
            # format keys are checked across all locales above; dynamic expressions
            # cannot be resolved by this small literal-only audit.
            if "\\(" in raw_key:
                continue
            key = json.loads('"' + raw_key + '"')
            if key not in english:
                errors.append(f"{path.relative_to(APP)}: missing localized literal {key!r}")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"PASS: {len(LOCALES)} locales; {len(english)} interface strings and "
          f"{len(tables[('en', 'InfoPlist.strings')])} permission descriptions each; "
          "keys, format arguments, syntax, brand, and Swift literals verified.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
