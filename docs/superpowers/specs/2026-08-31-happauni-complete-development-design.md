# HappaUni 完整功能交付设计

**日期：**2026-08-31  
**范围：**落实根目录 `claude.md` 的所有功能模块；不实施全局液态玻璃视觉重构。保留当前深色原生 SwiftUI 界面和已存在的侧栏悬浮操作区。

## 目标

交付 iPad 优先、iOS 17+ 的本地优先文档资料库：支持本地资料管理、PDF/Markdown/图片/EPUB 阅读、多账户 WebDAV、GitHub 私有仓库备份与恢复、OpenAI 兼容文档问答、设置和 LaTeX 编辑能力。

## 约束

- Swift 5.9、SwiftUI、SwiftData，部署目标 iOS 17.0。
- 用户密钥仅保存于 `KeychainStore`；不得写入 SwiftData、日志或 Git。
- WebDAV 缓存键必须包含账户标识和完整远程路径。
- GitHub 恢复不得覆盖本地较新内容；冲突应保留本地文件并写入可识别的恢复副本。
- 不引入全局液态玻璃主题；新增界面采用当前深色系统外观。
- 每个独立功能单元先写可失败的 `Testing` 测试，再实现、构建、提交并推送。

## 架构

### 资料库与阅读

`LibraryDocument`、`LibraryFolder` 和 `WebDAVAccount` 继续由 SwiftData 持久化。`ContentView` 负责侧栏、筛选、导入、选择和 sheet 路由；将阅读器、元数据编辑及文件夹创建保持为独立视图。`DocumentReaderView` 根据文档类型路由到 PDFKit、文本/Markdown、图片和 EPUB 阅读子视图。

### WebDAV

`WebDAVService` 负责协议请求，`WebDAVCacheStore` 负责路径隔离的缓存位置与清理。新增上传队列持久化待传任务、以指数退避重试；目录上传与下载都通过明确的进度模型向界面反馈。远程 ETag 与本地记录不匹配时，界面必须要求用户选择保留本地、保留远端或另存副本。

### GitHub

`GitHubService` 封装 OAuth、仓库与 Contents API；`SyncService` 负责文档及元数据的远程路径、递归枚举、下载恢复和冲突策略。恢复操作必须递归遍历 `documents/`，从元数据重建标签、文件夹、修改时间与同步状态。

### AI

`AIService` 使用 OpenAI Chat Completions 兼容 API。其职责包括 Keychain 配置、文档文本截取、SSE 流解析、请求取消和用量统计；`AIChatView` 管理会话历史、流式气泡和错误状态。聊天记录持久化到 SwiftData，API Key 始终留在 Keychain。

### EPUB 与 LaTeX

`EPUBService` 负责解包、容器/OPF/导航解析和章节资源定位；阅读界面提供章节选择、前后章、字体大小和主题设置。LaTeX 功能以轻量编辑器和 `WKWebView`/KaTeX 渲染预览组成，文稿存为本地 UTF-8 `.tex` 文件。

## 交付分段

1. **资料库与阅读完整性**：文件夹、元数据、全文搜索、PDF 工具栏、Markdown、图片和 EPUB。
2. **WebDAV 同步可靠性**：缓存、进度、上传队列、重试、ETag 冲突。
3. **GitHub 备份与恢复**：OAuth、仓库初始化、元数据清单、递归恢复与冲突副本。
4. **AI 会话**：模型配置、上下文、流式输出、历史、用量和错误提示。
5. **设置与专业工具**：外观、浏览器、缓存管理、LaTeX 编辑/预览。
6. **验证**：所有单元测试、指定 iPad 模拟器构建、关键手动流程和 Git 差异检查。

## 验收标准

- 可导入、分类、搜索、编辑元数据、删除并阅读每个支持的本地文件类型。
- EPUB 能显示章节、切换章节并保持阅读设置。
- WebDAV 可添加、浏览、下载、缓存、上传；网络失败后可重试且不覆盖冲突文件。
- GitHub 可连接、创建或使用私有仓库、同步打开文件、从仓库递归恢复文件与元数据。
- 用户配置 OpenAI 兼容端点后，可围绕当前文档进行流式问答；会话重启后可恢复且 Key 不可见。
- 设置页提供外观、浏览器与缓存操作；LaTeX 可编辑、保存并预览。
- `xcodebuild test` 与 iPad Pro 11-inch (M5) `xcodebuild build` 均成功。
