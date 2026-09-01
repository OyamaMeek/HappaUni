## [2026-09-01 16:47] 文件夹导入与分层备份

- **需求/问题描述**：
  > 导入时选择目标文件夹（含“未归档”），备份按文件夹层级保存，且不再写入固定的 `documents/` 与 `annotations` 目录；文件夹列表采用带颜色、数量和圆角选中态的展示效果。

- **实际实现的功能与改动**：
  - [导入分组]：导入文件先安全暂存，再显示目标文件夹选择器；支持“未归档”和任意嵌套文件夹。
  - [分层备份]：GitHub 与 WebDAV 按资料库文件夹层级同步，未分组文件保存到“未归档”；批注副本放在同级目录，不再使用固定 `documents/`、`annotations` 路径。
  - [资料库界面]：文件夹行增加彩色圆点、递归文件计数和圆角选中背景，并保留子文件夹操作。
  - [恢复兼容]：使用隐藏资料库清单记录远端路径与文件夹元数据，同时兼容旧版清单路径恢复。
  - [测试/验证]：`xcodebuild` iPhone Simulator Debug 构建成功；已安装并启动模拟器应用；`git diff --check` 通过。

- **涉及文件**：
  - `HappaUni/HappaUni/ContentView.swift` (+186 / -31)
  - `HappaUni/HappaUni/Services/SyncService.swift` (+104 / -74)

- **Git 提交**：`4cc5345 feat: organize import and backup folders`

---
