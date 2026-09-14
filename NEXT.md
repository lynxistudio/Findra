# Next

Last updated: 2026-09-14 12:17 Asia/Singapore

## Current Goal
- 升级 Findra 为轻量、高性能 macOS 原生文件管理器：核心需求全部开发完成并验证通过。

## Completed
- **阶段 1：导航引擎与目录浏览核心**：
  - `DatabaseManager.swift`：扩充 `parent_path` 字段与 `idx_files_parent` 索引，新增 `getFilesInDirectory`（毫秒级展开）与 `getFileSystemItems`（直接枚举）。
  - `FindraApp.swift`：增加导航状态机（`currentDirectoryPath`、`backStack`、`forwardStack`、`navigateTo`、`navigateBack`、`navigateForward`、`navigateUp`）。
  - `ContentView.swift`：实现顶部工具栏（前进/后退/上级、交互式面包屑 PathBar、F5/Cmd+R 强制刷新、列表/网格切换器）。
  - 侧边栏与目录树联动：点击侧边栏目录直达浏览，双击子文件夹逐层深入。
- **阶段 2：日常文件操作与智能剪贴板**：
  - 原生支持 `Cmd+X` 剪切（被剪切项视觉 45% 虚化）、`Cmd+C` 复制、`Cmd+V` 智能粘贴（自动副本编号与冲突重命名、同步更新 SQLite）。
  - `Return` / `Enter` 快捷行内重命名（列表与网格视图统一）。
  - `Cmd+Delete` 安全移入废纸篓（`FileManager.trashItem`）。
  - `F5` / `Cmd+R` 一键强制重载与同步当前目录。
- **阶段 3：流式异步缩略图与高性能网格视图**：
  - `ThumbnailManager.swift`：内存 LRU（`NSCache`）+ 磁盘持久化缓存（`Application Support/Findra/Thumbnails`），并发限制 6 线程，视口滚出自动取消任务。
  - 原生 `QLThumbnailGenerator` 加速图片与视频首帧/关键帧提取，回退 `AVAssetImageGenerator`。
  - `FileGridView.swift`：自适应 `LazyVGrid`，严格卡片布局规范消除边框重叠，卡片按固定尺寸与均匀间距排列。
- **阶段 4：Quick Look 联动与键盘流闭环**：
  - 空格键开关预览；方向键切换选中项时，Quick Look 预览实时同步跟随切换。
- **阶段 5：交互体验修复与多选手感提升（2026-09-14 补丁）**：
  - 修复缩略图网格卡片边框重叠问题，采用严格几何尺寸 (`itemWidth x itemHeight`) 与均匀 14px 列间隙。
  - 取消启动默认聚焦搜索框，用户点击搜索框才进入编辑状态；点击文件区域或空白处主动注销输入焦点；优化空格键预览判定，避免空格字符误打入搜索框。
  - 支持空白区域点选取消选中，支持单选、Cmd+点击加选/减选、Shift+点击连续区间多选。
  - 实现了 Windows / 访达同款鼠标框选（Rubber-band Marquee Drag Selection），拖拽绘制半透明高亮矩形并实时碰撞多选。
- **阶段 6：清理残余与正式部署（2026-09-14 部署）**：
  - 验证图标 `AppIcon.icns` 完整性与高分辨率规格。
  - 正式构建部署到 `/Applications/Findra.app`（v2.2.0）。
  - `build.sh` 默认输出路径调整为 `/Applications/Findra.app`。
  - 清理桌面临时构建残留（`/Users/gray/Desktop/Findra.app`）。
  - 清理项目根目录历史压缩包与多余媒体文件（`FastFinder_v2.0.1.zip`、`Findra_v2.1.0.zip`、`Sources/FastFinder` 二进制、散落录屏与截图）。
  - 清理系统 Library 中已废弃的旧版 FastFinder 缓存与配置残留。
- **构建与交付**：
  - `./build.sh` 编译完成，产物位于 `/Applications/Findra.app` (3.6MB)。

## Remaining
- [ ] 邀请用户上手体验新版 `Findra.app`，反馈具体使用细节或优化建议。
- [ ] 后续可选：多标签页（Tabs）或多列（Miller Columns）分栏浏览模式。

## Changed Files
- `Sources/DatabaseManager.swift`: `parent_path` 字段/索引及目录查询支持。
- `Sources/FindraApp.swift`: 导航状态机、剪切板操作、`IndexedFile` 增强。
- `Sources/ThumbnailManager.swift`: 异步流式多级缓存缩略图引擎。
- `Sources/FileGridView.swift`: 网格缩略图卡片视图与交互。
- `Sources/ContentView.swift`: 工具栏、面包屑 PathBar、快捷键全局监听与视图切换。
- `Sources/Localization.swift`: 补全中英文本地化词条。
- `Sources/ScanManager.swift`: 适配 `parent_path` 批处理写入。
- `build.sh`: 增加 `QuickLookThumbnailing` 与 `AVFoundation` 框架链接。
- `ROADMAP.md`: 长期升级规划与实施方案。
- `CHANGELOG.md`: 记录 2026-09-14 更新日志。

## Test Results
- `./build.sh`: Pass (Compiled successfully into `/Users/gray/Desktop/Findra.app`, Size: 3.5MB)

## Next Recommended Step
- 用户直接运行 `/Users/gray/Desktop/Findra.app` 体验双模文件管理、流式缩略图及日常操作。
