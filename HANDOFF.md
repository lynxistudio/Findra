# Handoff

Last updated: 2026-07-18 06:35 Asia/Singapore

## Current Goal
- Maintain Findra as an immediate, index-only macOS file search application.

## Current State
- Directory scans stage results before atomically replacing an existing index; incomplete scans preserve the prior index.
- Every configured root is fully reconciled at launch and on a five-minute schedule.
- The sidebar displays indexed folder and file totals per root.
- Search accepts filename substrings and uses a trigram FTS path for multi-term queries.
- Selected results can be dragged as standard file URLs or copied to Finder's pasteboard with `Cmd+C`.

## Important Decisions
- Do not traverse disks while a user is typing; searches query SQLite only.
- Do not silently exclude child directories by default. Only explicit user exclusion rules apply.
- Single-line search input is normalized to its first line to ignore hidden input-method/accessibility metadata.

## Changed Files
- `Sources/ScanManager.swift`: complete staged scans and FSEvents handling.
- `Sources/DatabaseManager.swift`: staging, search, and per-directory statistics.
- `Sources/FindraApp.swift`: scan lifecycle and sidebar statistics state.
- `Sources/SearchManager.swift`: one-line query normalization.
- `Sources/ContentView.swift`: index totals in sidebar.
- `Sources/FindraApp.swift` and `Sources/ContentView.swift`: multi-file copy/paste and context-menu copy.

## Deployment / External State
- Installed app: `/Applications/Findra.app`.
- GitHub: `https://github.com/lynxistudio/Findra`, branch `main`.

## Open Loops
- Large network-volume scans may take time; old search data remains available until each root commits its complete staged scan.

## Next Best Step
- Have the user retry a previously missing filename after this build, then investigate any remaining case with the exact filename and root path.
