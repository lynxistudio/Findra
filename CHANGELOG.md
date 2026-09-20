# Changelog

## 2026-09-20
- Fixed text pasting (`Cmd+V`), copying (`Cmd+C`), cutting (`Cmd+X`), and selecting all (`Cmd+A`) in all input fields: resolved an issue where global file browser key monitor intercepted `Cmd+V` (attempting to paste files instead of text) whenever typing in the search bar or sheets. Input fields now seamlessly accept pasted text, URLs, and paths from the clipboard.
- Added global `Cmd+A` shortcut to select all visible files when browsing the file list/grid.

## 2026-09-14
- Added full native macOS file drag-and-drop support (`NSDraggingSession`) to external applications: users can now drag single or multi-selected files directly from both Grid and Table views to other apps (Finder, Desktop, WeChat, Photoshop, VSCode, Chrome, Terminal, Trash, etc.), with native 48x48 icon drag stacks, count badges, and `[.copy, .generic, .move]` operation permissions. Preserves marquee box selection when dragging on empty grid canvas.
- Eliminated macOS spinning wheel (beachball) freeze during and after file deletion: completely offloaded synchronous directory enumeration (`refreshCurrentDirectory`), database aggregation stat queries (`getTotalFileCount`, `getDirectoryIndexStats`), file paste copying (`pasteFiles`), and full-text search sorting from the main thread to background utility/user-initiated queues.
- Fixed UI freeze when deleting/trashing large files on external drives or network volumes: file deletion operations (`trashItem` / `removeItem`) now run entirely on asynchronous background I/O threads with instant optimistic UI removal, eliminating spinning wheel / beachball freezes.
- Added instant "Delete Immediately" (`Option+Cmd+Delete`) and context menu option for external drives, bypassing slow cross-volume trash copying for large files.
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
