# Changelog

## 2026-09-14
- Upgraded Findra into a native macOS dual-mode file manager with instant FTS search and full hierarchical directory browsing.
- Fixed thumbnail grid card overlapping by establishing strict card geometry (`itemWidth x itemHeight`) and uniform grid cell spacing.
- Fixed search input focus conflict: search field no longer autofocuses on startup; clicking the file canvas or pressing Down Arrow exits search focus; Spacebar reliably opens Quick Look without inserting spaces into the search bar.
- Added full multi-selection interaction: single click, Cmd-click toggle, Shift-click range selection, and Windows/Finder-style rubber-band marquee drag box selection.
- Added interactive breadcrumb navigation (PathBar), folder traversal, and back/forward/up shortcuts (`Cmd+[`, `Cmd+]`, `Cmd+Up`).
- Added streaming asynchronous thumbnail grid view with two-tier cache (memory `NSCache` + disk `Application Support/Findra/Thumbnails`), native `QLThumbnailGenerator` hardware acceleration, video keyframe extraction, and scroll cancellation.
- Added full routine file operations: `Cmd+X` cut with visual dimming, `Cmd+C` copy, `Cmd+V` smart paste (with name collision resolution), `Return` inline rename, `Cmd+Delete` trash, and `F5` / `Cmd+R` force refresh.
- Synchronized Quick Look preview with arrow key selection navigation.
- Added `parent_path` column and index in SQLite for sub-millisecond directory querying.

## 2026-09-11
- Migrated the working copy to `smb://192.168.50.50/sata1-2/Work/Internal/Findra` (mounted locally at `/Volumes/sata1-2/Work/Internal/Findra`).

## 2026-07-18
- Fixed searches being polluted by hidden multi-line input metadata: Findra now searches the visible first line only.
- Added Finder-compatible copy/paste for selected search results, including multi-file selections.
- Prevented overlapping parent/child index roots from producing duplicate or unstable external-drive indexes.

## 2026-07-16
- Added complete atomic directory indexing, substring search improvements, and per-directory indexed file/folder counts.
