# Changelog

## 2026-09-11
- Migrated the working copy to `smb://192.168.50.50/sata1-2/Work/Internal/Findra` (mounted locally at `/Volumes/sata1-2/Work/Internal/Findra`).

## 2026-07-18
- Fixed searches being polluted by hidden multi-line input metadata: Findra now searches the visible first line only.
- Added Finder-compatible copy/paste for selected search results, including multi-file selections.
- Prevented overlapping parent/child index roots from producing duplicate or unstable external-drive indexes.

## 2026-07-16
- Added complete atomic directory indexing, substring search improvements, and per-directory indexed file/folder counts.
