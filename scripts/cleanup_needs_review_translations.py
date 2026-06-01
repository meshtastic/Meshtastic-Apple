#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path


PLACEHOLDER_RE = re.compile(r'%(?:\d+\$)?(?:@|lld|llu|ld|lu|d|i|u|f|g|e|s|c|x|X|o|p|a|A|F|E|G)')
ONLY_WRAPPER_RE = re.compile(r'[\s\-–—•·*_:;,.!?()\[\]{}<>/\\|`~"\']+')
DOMAIN_RE = re.compile(r'^[A-Za-z0-9][A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
EXACT_KEEP_SOURCE = {
	'—',
	'•',
	'• %@',
	'BIN',
	'https://',
	'meshtastic.pool.ntp.org',
	'paxcounter.log',
	'nil',
	'dBm',
	'mTLS',
	'x',
	'y',
}


def load_json(path: Path) -> dict:
	with path.open(encoding='utf-8') as handle:
		return json.load(handle)


def save_json(path: Path, payload: dict) -> None:
	with path.open('w', encoding='utf-8') as handle:
		json.dump(payload, handle, ensure_ascii=False, indent=2, sort_keys=True)
		handle.write('\n')


def load_do_not_translate(glossary_path: Path) -> set[str]:
	if not glossary_path.exists():
		return set()
	data = load_json(glossary_path)
	items = data.get('doNotTranslate') or data.get('do_not_translate') or []
	return set(items)


def normalize_placeholders(text: str) -> list[str]:
	placeholders = []
	for match in PLACEHOLDER_RE.findall(text):
		placeholders.append(re.sub(r'^%(?:\d+\$)?', '%', match))
	return placeholders


def strip_placeholders(text: str) -> str:
	return PLACEHOLDER_RE.sub('', text)


def canonicalize_format_structure(text: str) -> str:
	return PLACEHOLDER_RE.sub('%P', text)


def is_wrapper_only(text: str) -> bool:
	without_placeholders = strip_placeholders(text)
	without_wrappers = ONLY_WRAPPER_RE.sub('', without_placeholders)
	return not without_wrappers


def is_single_char_literal(text: str) -> bool:
	return len(text) == 1 and text.isalnum()


def is_code_like_literal(text: str, do_not_translate: set[str]) -> bool:
	if text in do_not_translate or text in EXACT_KEEP_SOURCE:
		return True
	if text.startswith(('http://', 'https://')) or '://' in text:
		return True
	if DOMAIN_RE.match(text):
		return True
	if text.endswith(('.log', '.json', '.yaml', '.yml', '.txt', '.csv', '.uf2', '.bin', '.xml', '.md')):
		return True
	if '/' in text and ' ' not in text:
		return True
	return False


def classify_issue(source: str, target: str, do_not_translate: set[str]) -> str | None:
	if source == target:
		return None

	source_placeholders = normalize_placeholders(source)
	target_placeholders = normalize_placeholders(target)
	if Counter(source_placeholders) != Counter(target_placeholders):
		return 'placeholder-mismatch'

	if is_wrapper_only(source):
		if canonicalize_format_structure(source) != canonicalize_format_structure(target):
			return 'wrapper-only-source'
		return None

	if is_single_char_literal(source):
		return 'single-character-literal'

	if is_code_like_literal(source, do_not_translate):
		return 'non-translatable-literal'

	if len(source) <= 3 and len(target) >= 12:
		return 'short-source-expanded'

	return None


def iter_string_units(strings: dict):
	for key, entry in strings.items():
		localizations = entry.get('localizations') or {}
		for locale, localization in localizations.items():
			string_unit = localization.get('stringUnit')
			if not string_unit:
				continue
			yield key, locale, string_unit


def main() -> int:
	parser = argparse.ArgumentParser(
		description='Reset obvious junk/non-translatable needs_review strings back to their source text.'
	)
	parser.add_argument(
		'xcstrings',
		nargs='?',
		default='Localizable.xcstrings',
		help='Path to the .xcstrings file (default: Localizable.xcstrings)',
	)
	parser.add_argument(
		'--glossary',
		default='scripts/glossary.json',
		help='Path to glossary JSON (default: scripts/glossary.json)',
	)
	parser.add_argument(
		'--apply',
		action='store_true',
		help='Write the cleanup back into the .xcstrings file.',
	)
	parser.add_argument(
		'--limit',
		type=int,
		default=80,
		help='Maximum detailed rows to print (default: 80)',
	)
	args = parser.parse_args()

	xcstrings_path = Path(args.xcstrings)
	glossary_path = Path(args.glossary)

	payload = load_json(xcstrings_path)
	strings = payload.get('strings', {})
	do_not_translate = load_do_not_translate(glossary_path)

	flagged: list[tuple[str, str, str, str]] = []
	by_reason: dict[str, int] = defaultdict(int)

	for source, locale, string_unit in iter_string_units(strings):
		if string_unit.get('state') != 'needs_review':
			continue
		target = string_unit.get('value', '')
		reason = classify_issue(source, target, do_not_translate)
		if not reason:
			continue
		flagged.append((reason, locale, source, target))
		by_reason[reason] += 1
		if args.apply:
			string_unit['value'] = source

	print(f'Flagged {len(flagged)} suspicious needs_review translations.')
	for reason in sorted(by_reason):
		print(f'  {reason}: {by_reason[reason]}')

	if flagged:
		print('')
		print('Cleanup list:')
		for reason, locale, source, target in flagged[:args.limit]:
			source_preview = source.replace('\n', '\\n')
			target_preview = target.replace('\n', '\\n')
			print(f'  [{reason}] {locale}: {source_preview} -> {target_preview}')
		if len(flagged) > args.limit:
			print(f'  ... {len(flagged) - args.limit} more')

	if args.apply:
		save_json(xcstrings_path, payload)
		print('')
		print(f'Updated {xcstrings_path}')

	return 0


if __name__ == '__main__':
	sys.exit(main())