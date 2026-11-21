#!/usr/bin/env python3
"""Copy one language's strings from a catalog Xcode has rewritten into ours.

When Xcode's translation tools save Localizable.xcstrings they rewrite the whole
file: every key is re-sorted and the format version changes. Committed as is,
that diff touches every line and conflicts with any other catalog change.

This takes the rewritten copy and copies just one language's entries into the
catalog as it was before the run, keeping its key order and format version.
Only that language changes; every other language and key stays byte for byte.

    python3 scripts/merge-catalog-locale.py --locale de --from /tmp/rewritten.xcstrings --into /tmp/before.xcstrings --output Localizable.xcstrings
"""
import argparse
import json
import sys


def dump(catalog):
    # Xcode's own layout: two-space indent, " : " between key and value, no trailing newline.
    return json.dumps(catalog, ensure_ascii=False, indent=2, separators=(',', ' : '))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--locale', required=True, help='language to copy, such as de or zh-Hans')
    parser.add_argument('--from', dest='source', required=True, help='the catalog Xcode rewrote')
    parser.add_argument('--into', required=True, help='the catalog as it was before the run')
    parser.add_argument('--output', required=True, help='where to write the result')
    args = parser.parse_args()

    with open(args.into, encoding='utf-8') as f:
        before_text = f.read()
    catalog = json.loads(before_text)
    if dump(catalog) != before_text:
        sys.exit(f'{args.into} is not in Xcode\'s layout, so it can\'t be rewritten without other changes')
    with open(args.source, encoding='utf-8') as f:
        rewritten = json.load(f)['strings']

    changed = 0
    for key, entry in catalog['strings'].items():
        unit = rewritten.get(key, {}).get('localizations', {}).get(args.locale)
        localizations = entry.get('localizations', {})
        if unit is None or localizations.get(args.locale) == unit:
            continue
        localizations[args.locale] = unit
        entry['localizations'] = dict(sorted(localizations.items()))
        changed += 1

    with open(args.output, 'w', encoding='utf-8') as f:
        f.write(dump(catalog))
    print(f'{changed} {args.locale} strings copied')


if __name__ == '__main__':
    main()
