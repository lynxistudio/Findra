# FastFinder

> **Instant file search for macOS — the Everything equivalent you've been missing.**

FastFinder is a native macOS file search engine built for speed. It indexes millions of files across local drives and network storage (NAS, NFS, SMB) using SQLite with FTS5 full-text search, delivers results in milliseconds, and stays up-to-date via FSEvents real-time monitoring.

[![Download](https://img.shields.io/badge/download-v2.0.1-brightgreen)](https://github.com/lynxistudio/FastFinder/releases/latest)
[![macOS](https://img.shields.io/badge/macOS-14.0%2B-blue)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.10-orange)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

---

## Table of Contents

- [Why FastFinder?](#why-fastfinder)
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

## Why FastFinder?

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

FastFinder gives you **total control** over what gets indexed, uses a lightweight SQLite FTS5 engine for sub-millisecond search, and keeps the index fresh with FSEvents real-time monitoring. It's:

- **Fast**: 50ms search across 500,000 files
- **Lightweight**: ~3MB binary, ~50MB RAM with 1M indexed files
- **Controllable**: You decide exactly which directories to index and which to exclude
- **Network-aware**: First-class support for NAS, NFS, and SMB volumes with configurable scan intervals
- **Native**: Pure SwiftUI, feels like a built-in macOS app

---

## Features

### Core Search

- **SQLite + FTS5 full-text search** — tokenized indexing with sub-millisecond query latency
- **Instant results** — debounced at 50ms, results appear as you type
- **Partial and substring matching** — find `report` in `Q4_financial_report_final.pdf`
- **Directory-aware** — instantly see whether a result is a file or a folder

### Index Management

- **Per-directory indexing** — add individual directories; only what you add gets indexed
- **Multiple directory types** — label each as Local, NFS, or SMB for appropriate scan strategies
- **Exclusion rules** — skip directories matching patterns like `node_modules`, `.git`, `__pycache__`, `vendor`, `build`, and more
- **13 default exclusions** — noise directories are skipped automatically

### Real-Time Updates

- **FSEvents monitoring** — local directories are watched for create/modify/delete/move events
- **Incremental indexing** — only changed files are re-scanned, not the entire directory
- **Atomic index replacement** — full rescans use `INSERT OR REPLACE` in a transaction to avoid index corruption
- **Scheduled full rescans** — network directories are fully rescanned every 5 minutes; local directories get incremental scans every 1 minute

### User Experience

- **Bilingual UI** — automatically follows your system language (English / Chinese)
- **Menu bar icon** — always accessible from the menu bar with `magnifyingglass` SF Symbol
- **Global hotkey** — `Cmd+Shift+Space` toggles the search window from anywhere
- **Native context menu** — right-click any result to rename, reveal in Finder, Quick Look, open, or move to trash
- **Inline renaming** — press Enter or use the context menu to rename files directly
- **Multi-select** — select multiple files for batch operations
- **Finder drag-and-drop** — drag one or more results to Finder to copy, or hold `Cmd` while dragging to move
- **Column sorting** — sort results by name, size, modification date, or path

### Technical

- **Zero third-party dependencies** — only Apple frameworks (SwiftUI, AppKit, Quartz) and the system SQLite library
- **Single binary** — compiled with `swiftc`, no Xcode project required (though you can use one)
- **Ad-hoc signed** — runs without a Developer ID certificate (right-click → Open on first launch)
- **macOS 14.0+** — leverages modern SwiftUI APIs and Swift concurrency

---

## Quick Start

### Option 1: Download Pre-built App (Recommended)

1. Go to the [Releases page](https://github.com/lynxistudio/FastFinder/releases)
2. Download `FastFinder_v2.0.1.zip` from the latest release
3. Unzip and drag `FastFinder.app` to your `/Applications` folder
4. On first launch, **right-click the app → Open** (or go to System Settings → Privacy & Security → Allow)

### Option 2: Build from Source

```bash
git clone https://github.com/lynxistudio/FastFinder.git
cd FastFinder
bash build.sh
```

The compiled `FastFinder.app` will be placed on your Desktop. Requires macOS 14.0+ and Xcode Command Line Tools (`xcode-select --install`).

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
| `Cmd+Shift+Space` | Toggle FastFinder window |
| `Enter` | Start renaming selected file |
| `Space` | Quick Look selected file |
| `Cmd+O` | Open selected file |
| `Cmd+Delete` | Move selected files to Trash |
| `Cmd+A` | Select all results |

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
│ SELECT * FROM files_fts     │
│ WHERE files_fts MATCH       │
│ 'report*'                   │
│ ORDER BY rank               │
│ LIMIT 10000                 ││
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
| FTS5 over LIKE queries | Tokenized search is 10-100x faster for large datasets |
| `fd` as primary scanner, `find` as fallback | `fd` is ~5x faster, respects `.gitignore`-style patterns |
| FSEvents for local, timed scans for network | Network filesystems don't reliably fire FSEvents |
| Atomic `INSERT OR REPLACE` transactions | Prevents index corruption if a scan is interrupted |
| `sips` + `iconutil` for icon generation | No Xcode asset catalog dependency; buildable with `swiftc` only |

---

## Project Structure

```
FastFinder/
├── Sources/
│   ├── FastFinderApp.swift      # @main entry, AppDelegate, data models, AppState
│   ├── ContentView.swift        # SwiftUI layout: sidebar, search bar, results table
│   ├── DatabaseManager.swift    # SQLite setup, schema, CRUD, FTS5 table management
│   ├── ScanManager.swift        # fd/find invocation, FSEvents watcher, incremental scan
│   ├── SearchManager.swift      # FTS5 MATCH query construction and execution
│   └── Localization.swift       # LocaleManager: auto-detect system language, all UI strings
├── build.sh                     # Build script: swiftc compile → .app bundle → ad-hoc sign
├── LICENSE                      # MIT License
└── README.md                    # This file
```

### File Descriptions

<details>
<summary><b>FastFinderApp.swift</b> — Application entry point and state</summary>

- `@main struct FastFinderApp`: SwiftUI App entry, injects `AppState` and `LocaleManager` as environment objects
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

- Schema: `directories`, `files`, `files_fts` (FTS5 virtual table), `excluded_patterns`
- FTS5 with `unicode61` tokenizer, content synchronization with `files` table
- Atomic operations: `replaceDirectoryEntries()` uses `DELETE + INSERT` inside a single transaction
- Full CRUD: add/remove/update directories; insert/delete/rename files; manage exclusion patterns
- Statistics: `getTotalFileCount()`, `getFilesByIds()`

</details>

<details>
<summary><b>ScanManager.swift</b> — File system scanner and watcher</summary>

- Primary scanner: `fd` with `--type f --type d --hidden` flags, parsed line-by-line
- Fallback scanner: `find` when `fd` is unavailable
- Exclusion filtering: matches directory names against `excludedPatterns` list
- Default exclusions (13 patterns): `.git`, `node_modules`, `__pycache__`, `.DS_Store`, `vendor`, `build`, `dist`, `.next`, `.nuxt`, `target`, `coverage`, `.terraform`, `.cache`
- FSEvents: `FSEventStreamCreate` with latency of 1.0s, callback dispatches to incremental scan
- Incremental scan: uses `fd --changed-within 2m` to identify recently changed files
- Pipe management: `readabilityHandler` on `FileHandle` to avoid deadlocks on large output

</details>

<details>
<summary><b>SearchManager.swift</b> — FTS5 query engine</summary>

- Query construction: sanitizes input, builds `MATCH` queries with proper escaping
- Tokenization: splits user input and constructs FTS5-compatible search terms
- Result: returns `[IndexedFile]` with ranking from FTS5 `rank` column
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
git clone https://github.com/lynxistudio/FastFinder.git
cd FastFinder

# Build (compiles Swift sources, creates .app bundle, ad-hoc signs)
bash build.sh

# Output: FastFinder.app on your Desktop
open ~/Desktop/FastFinder.app
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

### FastFinder vs. Everything (Windows)

| | Everything | FastFinder |
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

### FastFinder vs. Spotlight

| | Spotlight | FastFinder |
|---|---|---|
| Scope | System-wide, all indexed volumes | User-selected directories only |
| Control | Limited (Privacy exclusions) | Full (add/remove directories, exclusion rules) |
| Index freshness | Varies (mdworker schedule) | Real-time (FSEvents) + guaranteed periodic |
| Network storage | Unreliable | Reliable (timed full rescans) |
| Launch overhead | None (always running) | ~0.2s cold start |
| Content search | Yes (file contents, metadata) | No (file names only) |
| API | NSMetadataQuery (async) | Direct SQLite (sync, fast) |

### FastFinder vs. Find Any File

| | Find Any File | FastFinder |
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

Spotlight (`mdfind`) relies on the `mds`/`mdworker` daemons, which have documented reliability issues with network volumes and large file sets. FastFinder gives you a self-contained index that you fully control.
</details>

<details>
<summary><b>Does it index file contents?</b></summary>

No. FastFinder is a file **name** search tool, exactly like Everything on Windows. For content search, use Spotlight (`mdfind`) or a dedicated tool like `ripgrep`.
</details>

<details>
<summary><b>How much disk space does the index use?</b></summary>

Approximately 1-2 MB per 100,000 indexed files. A 500,000-file index occupies around 8-10 MB of disk space (SQLite database + FTS5 index).
</details>

<details>
<summary><b>Can I run it at login?</b></summary>

Yes. Go to System Settings → General → Login Items → add `FastFinder.app`. It will start silently with a menu bar icon.
</details>

<details>
<summary><b>Does it work on Apple Silicon / Intel?</b></summary>

The current build targets `arm64` (Apple Silicon). For Intel Macs, change the `-target` in `build.sh` to `x86_64-apple-macos14.0` and rebuild.
</details>

<details>
<summary><b>Can I use it without installing Xcode?</b></summary>

Yes. Download the pre-built `FastFinder.app` from the [Releases page](https://github.com/lynxistudio/FastFinder/releases). Xcode is only required if you want to build from source.
</details>

<details>
<summary><b>Why does macOS say the app is from an unidentified developer?</b></summary>

FastFinder is ad-hoc signed, not notarized by Apple. This is expected for open-source apps. Right-click the app and choose "Open" to bypass Gatekeeper on first launch.
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
- CLI companion tool (`fastfinder search "query"`)
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

FastFinder is inspired by:

- [**Everything**](https://www.voidtools.com/) by David Carpenter — the gold standard for instant file search on Windows
- [**Find Any File**](https://apps.tempel.org/FindAnyFile/) by Thomas Tempelmann — a great on-demand search tool for macOS
- [**fd**](https://github.com/sharkdp/fd) by David Peter — a fast and user-friendly alternative to `find`
- [**SQLite FTS5**](https://www.sqlite.org/fts5.html) — the full-text search engine that makes this possible

Built with Swift, SQLite, and a strong belief that macOS users deserve better file search.

---

*FastFinder is not affiliated with voidtools or the Everything project.*
