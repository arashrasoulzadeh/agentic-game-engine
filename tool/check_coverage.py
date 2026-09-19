#!/usr/bin/env python3
"""Require complete line coverage and detect omitted production sources."""

import argparse
from pathlib import Path
import re
import sys


def declarations_only(source):
    # Export barrels have no executable lines. The sole abstract System
    # interface is recognized by its exact declaration, not a filename waiver.
    text = re.sub(r'/\*.*?\*/|//[^\n]*', '', source, flags=re.S)
    text = re.sub(r'(?m)^\s*(?:import|export|library|part)\b[^;]*;', '', text)
    text = re.sub(
        r'abstract\s+class\s+System\s*\{\s*String\s+get\s+name\s*;'
        r'\s*void\s+update\(World\s+world,\s*double\s+dt\);\s*\}', '', text)
    return not text.strip()


def read_report(package, reports):
    lines = {}
    for report in reports:
        source = None
        for record in report.read_text().splitlines():
            if record.startswith('SF:'):
                path = Path(record[3:])
                source = (path if path.is_absolute() else package / path).resolve()
            elif record.startswith('DA:'):
                if source is None:
                    raise ValueError(f'{report}: line count without source')
                number, count = map(int, record[3:].split(',')[:2])
                counts = lines.setdefault(source, {})
                counts[number] = counts.get(number, 0) + count
    return lines


def check(package, reports):
    lines = read_report(package, reports)
    errors = []
    production = sorted(
        path.resolve() for directory in ('lib', 'bin')
        for path in (package / directory).rglob('*.dart'))
    hit = total = 0
    for source in production:
        relative = source.relative_to(package)
        content = source.read_text()
        if re.search(r'coverage:ignore', content):
            errors.append(f'{relative}: coverage exclusion is not allowed')
        counts = lines.get(source, {})
        if not counts and not declarations_only(content):
            errors.append(f'{relative}: missing executable source in coverage report')
        total += len(counts)
        hit += sum(count > 0 for count in counts.values())
        missed = [str(number) for number, count in sorted(counts.items()) if count == 0]
        if missed:
            errors.append(f'{relative}: uncovered lines {", ".join(missed)}')
    if not total:
        errors.append('No executable lines reported')
    percentage = 100 * hit / total if total else 0
    print(f'{package.name}: {hit}/{total} lines ({percentage:.2f}%)')
    for error in errors:
        print(f'  {error}', file=sys.stderr)
    return not errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('package', type=Path)
    parser.add_argument('reports', type=Path, nargs='*',
                        help='LCOV reports to merge; defaults to PACKAGE/coverage/lcov.info')
    args = parser.parse_args()
    package = args.package.resolve()
    reports = args.reports or [package / 'coverage/lcov.info']
    try:
        return 0 if check(package, reports) else 1
    except (OSError, ValueError) as error:
        print(error, file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
