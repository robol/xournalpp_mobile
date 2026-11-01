#!/usr/bin/env python3
"""Verify that all checked-in ARB and generated Intl catalogs have the same keys.

Run from any directory: python3 tool/check_l10n.py
The Flutter Intl plugin must regenerate files after editing an ARB message.
"""

import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LOCALES = ('en', 'de', 'pt')
CATALOG_KEY = re.compile(r'^    "([A-Za-z][A-Za-z0-9]*)":', re.MULTILINE)
GETTER_KEY = re.compile(r'^  String (?:get )?([A-Za-z][A-Za-z0-9]*)\b', re.MULTILINE)


def report_delta(label: str, actual: set[str], expected: set[str]) -> bool:
    missing = sorted(expected - actual)
    extra = sorted(actual - expected)
    if not missing and not extra:
        return True
    print(f'{label}: missing={missing}, unexpected={extra}', file=sys.stderr)
    return False


def main() -> int:
    arb = {}
    for locale in LOCALES:
        path = ROOT / 'lib' / 'l10n' / f'intl_{locale}.arb'
        data = json.loads(path.read_text(encoding='utf-8'))
        arb[locale] = {key for key in data if not key.startswith('@')}
    reference = arb['en']
    good = True
    for locale in LOCALES:
        good &= report_delta(f'{locale}.arb', arb[locale], reference)
        messages = (ROOT / 'lib' / 'generated' / 'intl' /
                    f'messages_{locale}.dart').read_text(encoding='utf-8')
        good &= report_delta(f'messages_{locale}.dart',
                             set(CATALOG_KEY.findall(messages)), reference)
    getters = (ROOT / 'lib' / 'generated' / 'l10n.dart').read_text(encoding='utf-8')
    good &= report_delta('l10n.dart', set(GETTER_KEY.findall(getters)), reference)
    if good:
        print(f'Localization catalogs agree: {len(reference)} keys × {len(LOCALES)} locales.')
    return 0 if good else 1


if __name__ == '__main__':
    raise SystemExit(main())
