# FastFinder

**macOS 超高速文件搜索工具** — Everything for macOS

FastFinder 是一款原生的 macOS 文件搜索神器，专为处理大量文件（NAS、NFS、SMB 等网络存储）而设计。它通过 SQLite + FTS5 全文索引 + FSEvents 实时监控，实现近乎即时的文件名搜索体验。支持中/英文界面（自动跟随系统语言）。

---

## 为什么需要 FastFinder？

macOS 自带的 Spotlight 和 Finder 搜索在面对海量文件时表现不佳：

- **索引更新迟缓**：Spotlight 对网络存储（NAS/NFS/SMB）的支持不稳定
- **搜索结果不完整**：常常漏掉文件，尤其是非系统卷上的内容
- **搜索速度慢**：面对数十万文件时，等待时间让人抓狂
- **不可控的索引范围**：无法精确指定只索引某些目录

Windows 用户有 [Everything](https://www.voidtools.com/)，而 macOS 用户现在有了 **FastFinder**。

## 核心特性

| 特性 | 说明 |
|------|------|
| 极速搜索 | 基于 SQLite FTS5 全文索引，毫秒级响应 |
| 实时更新 | FSEvents 监听文件变化，自动增量更新索引 |
| 网络存储支持 | 专为 NAS/NFS/SMB 优化，支持定时全量扫描 |
| 精确索引控制 | 按目录添加索引，可排除不需要的目录 |
| 排除规则 | 自定义排除规则，跳过 node_modules、.git 等噪音目录 |
| 原生体验 | 纯 SwiftUI 构建，原生 macOS 外观和手感 |
| 中英双语 | 自动跟随系统语言切换中/英文界面 |
| 菜单栏快捷呼出 | 菜单栏图标 + Cmd+Shift+Space 全局快捷键 |
| 零依赖 | 纯 Swift 编译，仅链接系统自带的 SQLite，无需任何第三方库 |

## 快速开始

### 下载使用

前往 [Releases](https://github.com/lynxistudio/FastFinder/releases) 页面下载最新的 `FastFinder.app`，解压后直接拖入 `/Applications` 文件夹即可使用。

> 首次打开如提示「无法验证开发者」，请在 Finder 中右键点击应用 →「打开」，或在「系统设置 → 隐私与安全性」中允许运行。

### 从源码编译

```bash
git clone https://github.com/lynxistudio/FastFinder.git
cd FastFinder
bash build.sh
```

编译产物 `FastFinder.app` 将生成在桌面（可在 `build.sh` 中修改 `OUTPUT_APP` 路径）。

**编译要求**：macOS 14.0+、Xcode Command Line Tools。

## 使用方法

1. **添加索引目录**：点击左侧「+」按钮，选择要索引的文件夹（支持本地、NFS、SMB）
2. **设置排除规则**：展开「排除规则」，添加需要跳过的目录名（如 `node_modules`）
3. **开始搜索**：在搜索框输入文件名关键词，结果实时显示
4. **文件操作**：右键文件可重命名、在 Finder 中显示、快速查看、移到废纸篓

## 项目结构

```
FastFinder/
├── Sources/
│   ├── FastFinderApp.swift      # App 入口、数据模型、全局状态管理
│   ├── ContentView.swift        # 主界面（SwiftUI）
│   ├── DatabaseManager.swift    # SQLite 数据库管理、索引 CRUD
│   ├── ScanManager.swift        # 文件扫描（fd/find）、FSEvents 监听
│   ├── SearchManager.swift      # FTS5 搜索查询
│   └── Localization.swift       # 中/英文本地化管理
├── build.sh                     # 编译构建脚本
├── LICENSE                      # MIT 许可证
└── README.md
```

## 技术原理

```
┌─────────────┐    ┌──────────────┐    ┌─────────────┐
│  fd / find  │─── │  SQLite+FTS5 │────│  SwiftUI UI  │
│  文件扫描    │    │  全文索引     │    │  搜索界面    │
└─────────────┘    └──────────────┘    └─────────────┘
        │                  │                   ▲
        ▼                  ▼                   │
┌─────────────┐    ┌──────────────┐            │
│  FSEvents   │    │  增量更新     │────────────┘
│  实时监听    │    │  原子替换     │
└─────────────┘    └──────────────┘
```

- **扫描引擎**：优先使用 `fd`（更快），fallback 到 `find`
- **索引引擎**：SQLite + FTS5 分词全文索引，支持拼音子串匹配
- **实时监控**：FSEvents 监听本地目录文件变化，增量更新索引
- **定时扫描**：网络存储目录每 5 分钟全量扫描，本地目录每 1 分钟增量更新
- **原子替换**：全量扫描使用原子替换策略，避免索引损坏

## macOS Everything 对比

| | Everything (Windows) | FastFinder (macOS) |
|------|------|------|
| 平台 | Windows | macOS 14.0+ |
| 索引引擎 | NTFS MFT 直读 | SQLite FTS5 |
| 实时更新 | NTFS USN Journal | FSEvents |
| 网络存储 | 有限支持 | 完整支持（NAS/NFS/SMB） |
| 安装包大小 | ~1.4 MB | ~3 MB |
| 界面框架 | Win32 | SwiftUI |
| 开源 | 否 | 是（MIT） |
| 语言 | 多语言 | 中/英（自动跟随系统） |

## 许可证

[MIT License](LICENSE)

## 致谢

FastFinder 的灵感来源于 Windows 上的 [Everything](https://www.voidtools.com/) 和 macOS 上的 [Find Any File](https://apps.tempel.org/FindAnyFile/)。

---

*Built with Swift, SQLite, and love for macOS.*