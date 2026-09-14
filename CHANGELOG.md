# Changelog

## 2026-09-14
- Enabled dynamic Quick Look (Space preview) following mouse selection clicks in list and grid views, matching macOS Finder behavior: clicking on another file seamlessly switches preview without closing or flickering the preview window; clearing selection closes preview.
- Fixed repeated disk/folder permission dialogs across app updates by anchoring a permanent designated requirement (`com.lynxistudio.findra`) and formal macOS usage descriptions (`NSDocumentsFolderUsageDescription`, `NSDownloadsFolderUsageDescription`, `NSRemovableVolumesUsageDescription`, `NSNetworkVolumesUsageDescription`).
- Fixed silent background startup: window now automatically activates to frontmost (`NSApp.activate(ignoringOtherApps: true)`) and centers itself upon launch instead of lingering unfocused or hidden behind other active windows.
- Compacted and repositioned directory sorting button: neatly grouped on the trailing side next to the List/Grid view switcher with `.fixedSize()` constraint, preventing awkward middle-toolbar spreading and maintaining macOS-standard toolbar rhythm.
- Added instant media resolution & duration display: reads image header via ImageIO (<0.1ms) and video/audio metadata via AVFoundation; displays resolution (e.g. `1920 × 1080`) in grid cards (between filename and size) and in dedicated Table columns.
- Added intuitive directory sorting button in the navigation toolbar: instant menu to sort by date modified, date created (local download time), file size, duration, and file name, with one-click ascending/descending toggle.
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
