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
## [2026-09-01 16:57] 修复文件夹资料展示

- **需求/问题描述**：
  > 点击“未归档”后右侧未展示文件。

- **实际实现的功能与改动**：
  - [文件夹浏览]：增加明确的文件夹浏览状态；点击未归档或普通文件夹会清除当前阅读文件并切换右侧内容。
  - [资料展示]：右侧以资料卡片展示未归档或所选文件夹（包含子文件夹）中的文档，点击卡片可打开对应文档。
  - [测试/验证]：Debug 构建成功，并安装启动 iPad 模拟器验证应用正常运行。

- **涉及文件**：
  - `HappaUni/HappaUni/ContentView.swift` (+87 / -1)

- **Git 提交**：`4402c22 fix: show selected folder documents`

---
## [2026-09-01 17:09] PDF 封面与快捷导入

- **需求/问题描述**：
  > 支持 PDF 封面显示；将资料库左上角加号改为“导入文件”；导入完成后自动打开导入的文件。

- **实际实现的功能与改动**：
  - [PDF 封面]：资料夹的文档卡片会读取 PDF 首页并显示为封面缩略图；读取失败时保留 PDF 图标作为回退。
  - [快捷导入]：资料库左上角操作改为带图标的“导入文件”按钮，点击后直接唤起系统文件选择器。
  - [自动打开]：导入并完成保存后，退出文件夹浏览并自动进入最后导入文档的阅读页。
  - [测试/验证]：`git diff --check` 通过；使用 Xcode Beta 的 iPhone Simulator Debug 构建成功。

- **涉及文件**：
  - `HappaUni/HappaUni/ContentView.swift` (+65 / -99)

- **Git 提交**：`4e4e644 feat: preview PDF covers after import`

---
## [2026-09-01 18:00] 废纸篓与 WebDAV 备份控制

- **需求/问题描述**：
  > 长按文件显示“归档到”（选择放入的文件夹）和“删除”；删除后移入废纸篓，废纸篓只备份到 GitHub、不备份到 WebDAV，并在 7 天后清理；设置中可关闭 WebDAV 备份。

- **实际实现的功能与改动**：
  - [文件操作]：资料卡片和侧栏文档均支持长按菜单，可选择“归档到”任意嵌套文件夹或移入废纸篓；废纸篓内支持恢复到目标文件夹和立即删除。
  - [废纸篓]：新增废纸篓入口与删除时间记录；应用启动及重新激活时自动清理保留超过 7 天的本地文件。
  - [备份策略]：废纸篓文件使用 GitHub 的“废纸篓”路径同步，并跳过 WebDAV 上传；备份清单保存废纸篓状态。
  - [设置]：新增“启用 WebDAV 自动备份”开关，关闭后停止自动上传至 WebDAV。
  - [测试/验证]：`git diff --check` 通过；iPhone Simulator Debug 构建成功；测试目标已编译，模拟器启动阶段中断了完整测试执行。

- **涉及文件**：
  - `HappaUni/HappaUni/ContentView.swift` (+237 / -30)
  - `HappaUni/HappaUni/Models/LibraryDocument.swift` (+4)
  - `HappaUni/HappaUni/Services/SyncService.swift` (+18 / -1)
  - `HappaUni/HappaUni/Views/SettingsView.swift` (+7)
  - `HappaUni/HappaUniTests/HappaUniTests.swift` (+16 / -1)

- **Git 提交**：`03bb7a8 feat: add trash and WebDAV backup controls`

---
