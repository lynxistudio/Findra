# Findra

> **Lightweight, High-Performance Native macOS File Manager & Instant Search**
> *The instant file search and fluid directory manager you've been missing.*

Findra is a native macOS dual-mode file manager built for pure speed and responsiveness. It seamlessly combines sub-millisecond SQLite FTS5 full-text indexing across local drives and network storage (NAS, NFS, SMB) with full hierarchical directory browsing, a hardware-accelerated streaming asynchronous thumbnail grid, and intuitive daily file operations (`Cmd+X/C/V`, inline rename, trash, Quick Look, and rubber-band marquee drag selection).

Findra was previously released as FastFinder. The app automatically migrates the old local index on first launch.

[![Download](https://img.shields.io/badge/download-v2.2.0-brightgreen)](https://github.com/lynxistudio/Findra/releases/latest)
[![macOS](https://img.shields.io/badge/macOS-14.0%2B-blue)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.10-orange)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

<p align="center">
  <img src="assets/findra-logo.png" alt="Findra logo" width="96" height="96">
</p>

## Preview

<p align="center">
  <img src="assets/findra-preview.gif" alt="Findra interface preview" width="760">
</p>

<p align="center">
  <img src="assets/screenshot-light.png" alt="Findra light mode screenshot" width="48%">
  <img src="assets/screenshot-dark.png" alt="Findra dark mode screenshot" width="48%">
</p>

---

## Table of Contents

- [Why Findra?](#why-findra)
- [Features](#features)
- [Quick Start](#quick-start)
- [Usage Guide](#usage-guide)
- [How It Works](#how-it-works)
- [Project Structure](#project-structure)
- [Build from Source](#build-from-source)
- [Comparison](#comparison)
- [FAQ](#faq)
- [Contributing](#contributing)
- [License](#license)
- [Acknowledgments](#acknowledgments)

---

## Why Findra?

### The Problem

macOS ships with Spotlight and Finder search, but both fall short when dealing with large file collections:

| Pain Point | Details |
|---|---|
| **Slow or broken network indexing** | Spotlight's `mdworker` frequently chokes on NFS/SMB volumes, leaving network files unsearchable. |
| **Incomplete results** | Finder search often misses files — especially on external or network drives. |
| **No granular index control** | You can't tell Spotlight "only index these 3 folders and nothing else." It's all-or-nothing. |
| **Search latency** | Across hundreds of thousands of files, Finder search can take seconds or even time out. |
| **Excessive resource usage** | `mds` and `mdworker` can peg CPU at 100% for hours when re-indexing large volumes. |

Windows users have had [Everything](https://www.voidtools.com/) — a lightning-fast NTFS search tool — for over a decade. macOS users had no equivalent. Until now.

### The Solution

Findra gives you **total control** over what gets indexed, uses a lightweight SQLite FTS5 engine for sub-millisecond search, and keeps the index fresh with FSEvents real-time monitoring. It's:

- **Fast**: 50ms search across 500,000 files
- **Lightweight**: ~3MB binary, ~50MB RAM with 1M indexed files
- **Controllable**: You decide exactly which directories to index and which to exclude
- **Network-aware**: First-class support for NAS, NFS, and SMB volumes with configurable scan intervals
- **Native**: Pure SwiftUI, feels like a built-in macOS app

---

## Features

### Dual-Mode File Management & Search

- **Hierarchical Directory Browsing** — drill down into subdirectories with instant response; double-click folders or use the interactive breadcrumb PathBar
- **History Navigation** — navigate Back (`Cmd+[`), Forward (`Cmd+]`), and Up (`Cmd+Up`) with full navigation history tracking
- **Instant FTS5 Search** — search across hundreds of thousands of files in milliseconds as you type
- **Sub-millisecond Folder Querying** — SQLite `parent_path` indexed queries (< 2ms) with seamless live `FileManager` fallback for non-indexed folders
- **Directory Refresh** — press `F5` or `Cmd+R` to immediately re-sync current directory contents

### Streaming Asynchronous Thumbnail Grid

- **Hardware-Accelerated Generation** — powered by Apple's native `QLThumbnailGenerator` framework
- **Video Keyframe Extraction** — automatically generates video previews using `AVAssetImageGenerator`
- **Two-Tier Intelligent Caching** — in-memory LRU (`NSCache`) + persistent disk cache (`~/Library/Application Support/Findra/Thumbnails`)
- **Strict Geometric Grid Layout** — fixed card bounds (`itemWidth x itemHeight`) with uniform column spacing completely eliminate card outline overlapping
- **Responsive Card Resizing** — seamlessly scale thumbnail sizes from 80px to 200px
- **Scroll Cancellation** — thumbnail generation tasks outside the visible viewport are cancelled automatically to maximize scrolling performance

### Routine File Operations & Clipboard

- **Cut (`Cmd+X`)** — marked items receive native 45% visual dimming until pasted
- **Copy (`Cmd+C`)** — copy selected files directly to the system clipboard
- **Smart Paste (`Cmd+V`)** — paste or move items into the current directory with automatic collision resolution (`filename (1).ext`) and instant SQLite index updates
- **Inline Rename (`Return` / `Enter`)** — rename directly without opening modal sheets
- **Move to Trash (`Cmd+Delete`)** — safely move files and directories to the macOS Trash (`FileManager.trashItem`)
- **Quick Look Follows Selection** — press `Space` to open Quick Look; moving selection with Arrow keys automatically updates the previewed file in real time

### Selection System & Marquee Drag Box

- **Single Click & Blank Deselect** — click item to select; click blank canvas to deselect all and blur search focus
- **Multi-Selection Modifiers** — `Cmd+Click` to toggle individual items; `Shift+Click` for contiguous range selection
- **Rubber-Band Marquee Drag Selection** — click and drag the mouse across the canvas to draw an interactive blue selection rectangle (Windows / Finder style) with live intersection selection and `Cmd` invert-drag support

### Index Management & Real-Time Monitoring

- **Per-directory indexing** — add individual directories; only what you add gets indexed
- **Multiple directory types** — label each as Local, NFS, or SMB for appropriate scan strategies
- **Exclusion rules** — skip noise directories matching patterns like `node_modules`, `.git`, `.cache`, `tmp`
- **FSEvents monitoring** — local directories are watched for real-time create/modify/delete/move events
- **Incremental indexing** — only changed files are re-scanned, not the entire directory
- **Atomic index replacement** — full rescans use `INSERT OR REPLACE` in transactions to avoid corruption

### User Experience & Technical

- **Bilingual UI** — automatically follows system language (English / Chinese)
- **Menu bar icon & Global Hotkey** — `Cmd+Shift+Space` toggles the window from anywhere
- **Zero third-party dependencies** — pure Swift using only Apple frameworks (SwiftUI, AppKit, Quartz, QuickLookThumbnailing, AVFoundation) and system SQLite
- **Single binary** — lightweight ~3.6MB app bundle built with `swiftc`, no Xcode IDE overhead required

---

## Quick Start

### Option 1: Download Pre-built App (Recommended)

1. Go to the [Releases page](https://github.com/lynxistudio/Findra/releases)
2. Download `Findra_v2.1.0.zip` from the latest release
3. Unzip and drag `Findra.app` to your `/Applications` folder
4. On first launch, **right-click the app → Open** (or go to System Settings → Privacy & Security → Allow)

### Option 2: Build from Source

```bash
git clone https://github.com/lynxistudio/Findra.git
cd Findra
bash build.sh
```

The compiled `Findra.app` will be placed on your Desktop. Requires macOS 14.0+ and Xcode Command Line Tools (`xcode-select --install`).

---

## Usage Guide

### Adding Index Directories

1. Click the **+** button in the sidebar under "Indexed Directories"
2. Click **Browse** to select a folder via the native folder picker, or type/paste a path
3. Choose the directory type: **Local** (FSEvents monitoring), **NFS**, or **SMB**
4. Click **Add** — the directory will be scanned immediately

### Exclusion Rules

1. Expand the **Exclusion Rules** section in the sidebar
2. Click **+** to add a new pattern (e.g., `node_modules`, `.terraform`, `dist`)
3. Directories matching any pattern will be skipped during indexing
4. Click the **x** on any rule to remove it

### Searching

1. Type a file name or partial keyword in the search bar (e.g., `invoice`, `2024`, `.pdf`)
2. Results appear instantly, sorted by relevance
3. Click any column header to sort by name, size, date, or path
4. Double-click a result to open it, or use the context menu for more options
5. Drag one or more selected results to Finder to copy them; hold `Cmd` while dragging to move them

### File Operations

Right-click any search result to access:
- **Rename** — edit the file name inline
- **Show in Finder** — reveal the file in a Finder window
- **Quick Look** — preview the file with Quick Look (images, PDFs, text, etc.)
- **Open** — open with the default application
- **Move to Trash** — send the file to Trash

You can also drag selected search results directly into Finder. Normal drag copies the files; `Cmd` + drag moves them.

### Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `Cmd+Shift+Space` | Toggle Findra window from anywhere |
| `Space` | Toggle Quick Look preview (synchronized with Arrow navigation) |
| `Cmd+[` | Navigate Back in folder history |
| `Cmd+]` | Navigate Forward in folder history |
| `Cmd+Up` | Navigate to Parent directory |
| `F5` / `Cmd+R` | Force refresh current directory |
| `Cmd+X` | Cut selected files (visual dimming) |
| `Cmd+C` | Copy selected files |
| `Cmd+V` | Paste files into current directory (auto conflict resolution) |
| `Return` / `Enter` | Inline rename selected file |
| `Cmd+Delete` | Move selected files to Trash |
| `Cmd+A` | Select all files in current view |
| `Cmd+1` / `Cmd+2` | Switch between List and Grid view |
| `Esc` | Clear search focus or dismiss rename/selection |

---

## How It Works

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      SwiftUI Frontend                       │
│  ┌──────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │ Sidebar  │  │ Search Bar   │  │ Results Table        │  │
│  │ (dirs)   │  │ (FTS5 query) │  │ (sort/filter/select) │  │
│  └──────────┘  └──────────────┘  └──────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│                     Business Logic                          │
│  ┌────────────┐  ┌──────────────┐  ┌───────────────────┐   │
│  │ AppState   │  │ ScanManager  │  │ LocaleManager     │   │
│  │ (Observable│  │ (fd/find +   │  │ (system language  │   │
│  │  Object)   │  │  FSEvents)   │  │  auto-detect)     │   │
│  └────────────┘  └──────────────┘  └───────────────────┘   │
├─────────────────────────────────────────────────────────────┤
│                     Data Layer                              │
│  ┌─────────────────────┐  ┌────────────────────────────┐   │
│  │ DatabaseManager     │  │ SearchManager              │   │
│  │ (SQLite CRUD,       │  │ (FTS5 query builder,       │   │
│  │  schema migration,  │  │  tokenization,             │   │
│  │  atomic batch ops)  │  │  result ranking)           │   │
│  └─────────────────────┘  └────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### Indexing Pipeline

```
Directory Added
      │
      ▼
┌──────────┐     ┌──────────────┐     ┌──────────────────┐
│ fd/find  │────▶│ Parse &      │────▶│ SQLite INSERT    │
│ walk     │     │ filter by    │     │ OR REPLACE       │
│          │     │ exclusions   │     │ (atomic txn)     │
└──────────┘     └──────────────┘     └──────────────────┘
                                            │
                                            ▼
                                       FTS5 Tokenizer
                                            │
                                            ▼
                                     ┌──────────────┐
                                     │ Searchable    │
                                     │ Index         │
                                     └──────────────┘

FSEvents Event (create/modify/delete)
      │
      ▼
┌──────────────┐     ┌──────────────────┐
│ Match against│────▶│ Incremental      │
│ indexed dir  │     │ INSERT/UPDATE/   │
│              │     │ DELETE           │
└──────────────┘     └──────────────────┘
```

### Search Flow

```
User types "report"
      │
      ▼
┌─────────────────┐
│ Debounce (50ms)  │
│ Combine pipeline │
└─────────────────┘
      │
      ▼
┌─────────────────────────────┐
│ Single token: file_name LIKE │
│ Multi-token: files_fts MATCH │
│ LIMIT 10000                  │
└─────────────────────────────┘
      │
      ▼
┌─────────────────┐
│ SwiftUI Table   │
│ render          │
└─────────────────┘
```

### Key Design Decisions

| Decision | Rationale |
|---|---|
| SQLite over CoreData/Spotlight | Portability, speed, zero background daemon, full control |
| LIKE + FTS5 search | Single-token substring search stays flexible; multi-token FTS keeps larger queries fast |
| `fd` as primary scanner, `find` as fallback | `fd` is fast when installed, while `/usr/bin/find` keeps the app dependency-free |
| FSEvents for local, timed scans for network | Network filesystems don't reliably fire FSEvents |
| Atomic `INSERT OR REPLACE` transactions | Prevents index corruption if a scan is interrupted |
| `sips` + `iconutil` for icon generation | No Xcode asset catalog dependency; buildable with `swiftc` only |

---

## Project Structure

```
Findra/
├── Sources/
│   ├── FindraApp.swift          # @main entry, AppDelegate, data models, AppState, navigation state machine
│   ├── ContentView.swift        # SwiftUI layout: sidebar, toolbar, PathBar, search bar, table/grid
│   ├── FileGridView.swift       # Streaming thumbnail grid view, card geometry, marquee drag box selection
│   ├── ThumbnailManager.swift   # Multi-tier async streaming thumbnail engine (QLThumbnailGenerator + AVFoundation)
│   ├── DatabaseManager.swift    # SQLite setup, schema, parent_path indexing, CRUD, FTS5 table management
│   ├── ScanManager.swift        # fd/find invocation, FSEvents watcher, staged scans, incremental scan
│   ├── SearchManager.swift      # FTS5 MATCH query construction and execution
│   └── Localization.swift       # LocaleManager: auto-detect system language, all UI strings (English/Chinese)
├── build.sh                     # Build script: swiftc compile → .app bundle → ad-hoc sign
├── ROADMAP.md                   # Long-term feature roadmap and architectural plans
├── CHANGELOG.md                 # Version history and release notes
├── HANDOFF.md                   # Agent and developer handoff documentation
├── NEXT.md                      # Active sprint tracking and next tasks
├── LICENSE                      # MIT License
└── README.md                    # This file
```

### File Descriptions

<details>
<summary><b>FindraApp.swift</b> — Application entry point and state</summary>

- `@main struct FindraApp`: SwiftUI App entry, injects `AppState` and `LocaleManager` as environment objects
- `AppDelegate`: Manages menu bar icon, global hotkey (`Cmd+Shift+Space`), and window lifecycle
- `AppState`: Central `ObservableObject` — owns `DatabaseManager`, `ScanManager`, `SearchManager`; coordinates indexing, search, and file operations
- `DirectoryType`: Enum for `local` / `nfs` / `smb` with localized display names
- Data models: `IndexDirectory`, `IndexedFile` with formatted size and date properties

</details>

<details>
<summary><b>ContentView.swift</b> — Main user interface</summary>

- Three-column layout: sidebar (directories + exclusions) | search bar | results table
- `addDirectorySheet`: Folder picker with path input, type selector (Local/NFS/SMB)
- `excludedPatternSheet`: Exclusion rule manager with add/remove
- Results table with sortable columns (Name, Size, Modified, Path), multi-select, context menu
- Inline file renaming with Enter-to-commit / Escape-to-cancel
- `DisclosureGroup` for collapsible exclusion rules section

</details>

<details>
<summary><b>DatabaseManager.swift</b> — SQLite persistence layer</summary>

- Schema: `directories`, `files`, `files_fts` (FTS5 virtual table), `excluded_dirs`
- FTS5 with `unicode61` tokenizer, content synchronization with `files` table
- Atomic operations: `replaceDirectoryEntries()` uses `DELETE + INSERT` inside a single transaction
- Full CRUD: add/remove/update directories; insert/delete/rename files; manage exclusion patterns
- Statistics: `getTotalFileCount()`, `getFilesByIds()`

</details>

<details>
<summary><b>ScanManager.swift</b> — File system scanner and watcher</summary>

- Primary scanner: `fd` with `--type` and `--absolute-path`, parsed line-by-line
- Fallback scanner: `find` when `fd` is unavailable
- Exclusion filtering: matches directory names against `excludedPatterns` list
- Default exclusions (13 patterns): `.git`, `node_modules`, `.cache`, `tmp`, `temp`, `Trash`, `Recycle Bin`, `@eaDir`, `#recycle`, `.recycle`, `System Volume Information`, `.DS_Store`, `Thumbs.db`
- FSEvents: `FSEventStreamCreate` with file-level events, callback updates changed paths in the index
- Incremental scan: uses the last scan timestamp with the `find` fallback and FSEvents for local changes
- Pipe management: `readabilityHandler` on `FileHandle` to avoid deadlocks on large output

</details>

<details>
<summary><b>SearchManager.swift</b> — FTS5 query engine</summary>

- Query construction: trims input and splits multi-word searches into tokens
- Search strategy: single-token searches use `LIKE`; multi-token searches use FTS5 `MATCH`
- Result: returns `[IndexedFile]` records from the SQLite index
- Limit: 10,000 results per query for UI performance

</details>

<details>
<summary><b>Localization.swift</b> — System language detection and string provider</summary>

- `LocaleManager`: Reads `Locale.preferredLanguages` on init, sets `isChinese` boolean
- All UI strings are computed properties returning either English or Chinese based on `isChinese`
- Covers: sidebar labels, search placeholders, table headers, context menu items, scan status messages, folder picker prompts, confirmation dialogs
- No manual language switching — automatically follows the system language

</details>

---

## Build from Source

### Prerequisites

- macOS 14.0 or later
- Xcode Command Line Tools (`xcode-select --install`)
- Optional: [`fd`](https://github.com/sharkdp/fd) (`brew install fd`) for faster scanning (falls back to `find` if unavailable)

### Build Steps

```bash
# Clone the repository
git clone https://github.com/lynxistudio/Findra.git
cd Findra

# Build (compiles Swift sources, creates .app bundle, ad-hoc signs)
bash build.sh

# Output: Findra.app on your Desktop
open ~/Desktop/Findra.app
```

### What `build.sh` Does

1. Compiles all `.swift` files in `Sources/` using `swiftc` with `arm64-apple-macos14.0` target
2. Links against SwiftUI, AppKit, Quartz, and libsqlite3 system frameworks
3. Creates the `.app` bundle structure (`Contents/MacOS/`, `Contents/Resources/`)
4. Copies `AppIcon.icns` into the bundle
5. Generates `Info.plist` with bundle metadata
6. Ad-hoc codesigns the bundle (`codesign --force --deep --sign -`)

### Customizing the Build

Edit `build.sh` to change:
- `OUTPUT_APP` — where the `.app` is placed (default: Desktop)
- `-target` — architecture (default: `arm64-apple-macos14.0`)
- Icon path (`ICNS_PATH`) — path to your custom `.icns` file

---

## Comparison

### Findra vs. Everything (Windows)

| | Everything | Findra |
|---|---|---|
| Platform | Windows | macOS 14.0+ |
| Indexing engine | NTFS Master File Table (MFT) | SQLite + FTS5 |
| Real-time updates | NTFS USN Journal | FSEvents + timed rescans |
| Network storage | Limited (ETP server) | Full support (NAS/NFS/SMB) |
| Binary size | ~1.4 MB | ~2.9 MB |
| RAM usage (1M files) | ~100 MB | ~50 MB |
| UI framework | Win32 | SwiftUI (native macOS) |
| Open source | No | Yes (MIT) |
| UI language | 30+ languages | English / Chinese (auto-detect) |
| Wildcard search | Yes | Yes (FTS5 tokenization) |
| Regex search | Yes | No (planned) |
| File content search | No | No (file name only) |

### Findra vs. Spotlight

| | Spotlight | Findra |
|---|---|---|
| Scope | System-wide, all indexed volumes | User-selected directories only |
| Control | Limited (Privacy exclusions) | Full (add/remove directories, exclusion rules) |
| Index freshness | Varies (mdworker schedule) | Real-time (FSEvents) + guaranteed periodic |
| Network storage | Unreliable | Reliable (timed full rescans) |
| Launch overhead | None (always running) | ~0.2s cold start |
| Content search | Yes (file contents, metadata) | No (file names only) |
| API | NSMetadataQuery (async) | Direct SQLite (sync, fast) |

### Findra vs. Find Any File

| | Find Any File | Findra |
|---|---|---|
| Search method | On-demand filesystem walk | Pre-built index |
| Speed (500K files) | 10-30 seconds | <100ms |
| UI | AppKit | SwiftUI |
| Price | Free (with nag) | Free (MIT) |
| Open source | No | Yes |

---

## FAQ

<details>
<summary><b>Why not use Spotlight's mdfind?</b></summary>

Spotlight (`mdfind`) relies on the `mds`/`mdworker` daemons, which have documented reliability issues with network volumes and large file sets. Findra gives you a self-contained index that you fully control.
</details>

<details>
<summary><b>Does it index file contents?</b></summary>

No. Findra is a file **name** search tool, exactly like Everything on Windows. For content search, use Spotlight (`mdfind`) or a dedicated tool like `ripgrep`.
</details>

<details>
<summary><b>How much disk space does the index use?</b></summary>

Approximately 1-2 MB per 100,000 indexed files. A 500,000-file index occupies around 8-10 MB of disk space (SQLite database + FTS5 index).
</details>

<details>
<summary><b>Can I run it at login?</b></summary>

Yes. Go to System Settings → General → Login Items → add `Findra.app`. It will start silently with a menu bar icon.
</details>

<details>
<summary><b>Does it work on Apple Silicon / Intel?</b></summary>

The current build targets `arm64` (Apple Silicon). For Intel Macs, change the `-target` in `build.sh` to `x86_64-apple-macos14.0` and rebuild.
</details>

<details>
<summary><b>Can I use it without installing Xcode?</b></summary>

Yes. Download the pre-built `Findra.app` from the [Releases page](https://github.com/lynxistudio/Findra/releases). Xcode is only required if you want to build from source.
</details>

<details>
<summary><b>Why does macOS say the app is from an unidentified developer?</b></summary>

Findra is ad-hoc signed, not notarized by Apple. This is expected for open-source apps. Right-click the app and choose "Open" to bypass Gatekeeper on first launch.
</details>

<details>
<summary><b>How do I contribute?</b></summary>

See [Contributing](#contributing). Pull requests, bug reports, and feature suggestions are all welcome.
</details>

---

## Contributing

Contributions are welcome. Here's how:

1. **Fork** the repository
2. **Create a branch** for your feature or fix
3. **Make your changes** — follow the existing code style and add comments for complex logic
4. **Test** — build with `bash build.sh` and verify the `.app` works
5. **Submit a Pull Request** with a clear description of what you changed and why

### Contribution Ideas

- Intel (x86_64) build support
- Regular expression search
- Dark/light mode toggle (currently follows system)
- Saved search presets
- Export search results to CSV/JSON
- CLI companion tool (`findra search "query"`)
- Homebrew cask distribution

### Code Style

- Swift 5.10+, SwiftUI conventions
- Mark classes `final` by default
- Use `weak self` in async closures
- Prefer `struct` over `class` for value types
- Keep computed properties simple (O(1) where possible)

---

## License

MIT License. See [LICENSE](LICENSE) for full text.

---

## Acknowledgments

Findra is inspired by:

- [**Everything**](https://www.voidtools.com/) by David Carpenter — the gold standard for instant file search on Windows
- [**Find Any File**](https://apps.tempel.org/FindAnyFile/) by Thomas Tempelmann — a great on-demand search tool for macOS
- [**fd**](https://github.com/sharkdp/fd) by David Peter — a fast and user-friendly alternative to `find`
- [**SQLite FTS5**](https://www.sqlite.org/fts5.html) — the full-text search engine that makes this possible

Built with Swift, SQLite, and a strong belief that macOS users deserve better file search.

---

*Findra is not affiliated with voidtools or the Everything project.*
