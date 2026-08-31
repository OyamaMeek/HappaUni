```markdown
# HappaUni 复刻版 - 完整开发指南

> **项目代号**: HappaUni
> **目标平台**: iOS 17.0+
> **开发语言**: Swift 5.9 + SwiftUI
> **商业模式**: 完全免费 + 开源

---

## 📑 目录

1. [项目概述](#1-项目概述)
2. [功能规格清单](#2-功能规格清单)
3. [UI 设计系统](#3-ui-设计系统)
4. [技术架构设计](#4-技术架构设计)
5. [核心模块实现](#5-核心模块实现)
6. [开发路线图](#6-开发路线图)
7. [第三方依赖](#7-第三方依赖)
8. [App Store 上架指南](#8-app-store-上架指南)
9. [风险与应对策略](#9-风险与应对策略)

---

## 1. 项目概述

### 1.1 产品定位
一款面向知识工作者的轻量级文档管理与阅读应用，支持 PDF、Markdown、EPUB 等格式，集成 AI 智能问答（用户自备 API Key），支持 WebDAV 多账户云存储，提供 Git 自动同步功能。完全免费，无内购。

### 1.2 核心价值主张
- **隐私至上**: 本地优先，数据不上传第三方服务器
- **AI 增强**: 基于文档内容的智能问答（用户自备 OpenAI API Key）
- **WebDAV 支持**: 连接多个 WebDAV 服务器（坚果云、Nextcloud、Synology 等）
- **Git 自动同步**: 打开过的文件自动提交到 GitHub 私有仓库，跨设备同步
- **极简设计**: iPad 优化的双栏布局，暗色模式原生支持
- **完全免费**: 无订阅、无广告、无数据收集

### 1.3 目标用户
- 学术研究人员（论文阅读 + 笔记）
- 程序员（技术文档 + Markdown）
- 知识管理爱好者（PDF 标注 + 跨设备同步）

---

## 2. 功能规格清单

### 2.1 功能模块矩阵

| 功能模块 | 优先级 | 技术难度 | 预估工时 |
|---------|--------|---------|----------|
| **文件管理** |
| 本地文件导入 | P0 | ⭐⭐ | 2 周 |
| 文件夹分层管理 | P0 | ⭐⭐ | 1 周 |
| WebDAV 多账户管理 | P0 | ⭐⭐⭐⭐ | 5 周 |
| WebDAV 文件上传/下载 | P0 | ⭐⭐⭐ | 3 周 |
| 文件拖拽排序 | P2 | ⭐⭐ | 1 周 |
| **文档阅读** |
| PDF 阅读器 | P0 | ⭐⭐⭐ | 3 周 |
| Markdown 渲染 | P0 | ⭐⭐ | 2 周 |
| EPUB 阅读器 | P1 | ⭐⭐⭐⭐ | 3 周 |
| **AI 功能** |
| OpenAI API 集成（用户自备 Key） | P0 | ⭐⭐⭐ | 3 周 |
| 文档智能问答 | P0 | ⭐⭐⭐⭐ | 4 周 |
| 模型配置管理 | P0 | ⭐⭐ | 1 周 |
| 对话历史记录 | P1 | ⭐⭐ | 1 周 |
| **Git 同步** |
| GitHub OAuth 认证 | P1 | ⭐⭐⭐ | 2 周 |
| 自动提交打开的文件 | P1 | ⭐⭐⭐⭐ | 3 周 |
| Clone 私有仓库 | P1 | ⭐⭐⭐ | 2 周 |
| 文件冲突处理 | P1 | ⭐⭐⭐⭐ | 2 周 |
| **专业工具** |
| LaTeX 环境 | P2 | ⭐⭐⭐⭐⭐ | 6 周 |
| **设置与配置** |
| 通用与外观设置 | P0 | ⭐⭐ | 2 周 |
| 浏览器配置 | P1 | ⭐⭐ | 1 周 |
| 存储与缓存管理 | P1 | ⭐⭐ | 1 周 |

**总计工时**: 约 **48 周**（GPT 辅助开发可缩短至 30-35 周）

### 2.2 功能变更说明



#### 核心功能说明

**Git 同步机制**:
```
用户打开文件 → 自动提交到 GitHub 私有仓库 → 换设备后 Clone 下来
```

工作流程：
1. 用户首次使用时，通过 GitHub OAuth 授权
2. App 在用户的 GitHub 账户下创建/连接一个私有仓库（如 `HappaUni-sync`）
3. 每次打开文件时，自动提交该文件及其元数据到仓库
4. 换设备后，输入 GitHub Token，自动 Clone 仓库并恢复文件列表

---

## 3. UI 设计系统

### 3.1 整体布局架构

#### 三栏式布局（iPad 横屏优化）

```
┌──────────────────────────────────────────────────────────────────┐
│  [资料库] [+] [🗑] [⚙️] [⬜️]   📄 iOS应用逆向与安全之道.pdf  ✕  │
├─────────────┬────────────────────────────────────────────────────┤
│             │                                                    │
│ 🌐 WebDAV   │                  欢迎使用 HappaUni                  │
│   服务器列表 │                                                    │
│             │   HappaUni 可以管理资料库，打开和播放文件...          │
│ 📁 坚果云    │                                                    │
│   ├ 工作文档 │              三步开始                               │
│   └ 个人笔记 │   1. 点资料库顶部的"+"，导入文件或连接 WebDAV      │
│             │   2. 点一个文件即可打开。                          │
│ 📁 Nextcloud│   3. 直接向 AI 助手提问（需配置 OpenAI API Key）   │
│   ├ 项目资料 │                                                    │
│   └ 照片备份 │   已启用 GitHub 同步：打开的文件会自动备份         │
│             │                                                    │
│ 🐙 GitHub   │              主内容区域                            │
│   同步状态   │          (文档渲染/阅读区域)                       │
│   ✓ 已同步   │                                                    │
│             │                                                    │
│ 📱 本地文件  │                                                    │
│   ├ 欢迎.md  │                                                    │
│   └ iOS.pdf │                                                    │
│             │                                                    │
│  侧边栏      │                                                    │
│  (280pt)    │                                                    │
└─────────────┴────────────────────────────────────────────────────┘
```

### 3.2 颜色系统（Dark Mode）

#### 色板定义

```swift
extension Color {
    // 背景层级
    static let appBackground = Color(hex: "#000000")
    static let sidebarBackground = Color(hex: "#1C1C1E")
    static let cardBackground = Color(hex: "#2C2C2E")
    static let secondaryBackground = Color(hex: "#3A3A3C")
  
    // 文字颜色
    static let primaryText = Color(hex: "#FFFFFF")
    static let secondaryText = Color(hex: "#E5E5E7")
    static let tertiaryText = Color(hex: "#8E8E93")
    static let disabledText = Color(hex: "#636366")
  
    // 强调色
    static let brandBlue = Color(hex: "#0A84FF")
    static let successGreen = Color(hex: "#30D158")
    static let warningOrange = Color(hex: "#FF9F0A")
    static let dangerRed = Color(hex: "#FF3B30")
    static let webdavPurple = Color(hex: "#BF5AF2")
    static let githubOrange = Color(hex: "#F9826C")
  
    // 分隔线
    static let dividerColor = Color(hex: "#38383A")
    static let borderColor = Color(hex: "#48484A")
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
```

### 3.3 字体系统

```swift
extension Font {
    static let appTitle = Font.system(size: 36, weight: .bold, design: .default)
    static let sectionTitle = Font.system(size: 22, weight: .semibold)
    static let subsectionTitle = Font.system(size: 18, weight: .semibold)
    static let bodyText = Font.system(size: 15, weight: .regular)
    static let caption = Font.system(size: 13, weight: .regular)
    static let footnote = Font.system(size: 11, weight: .regular)
    static let code = Font.system(size: 13, weight: .regular, design: .monospaced)
}
```

### 3.4 核心组件设计

#### 3.4.1 左侧边栏（带 GitHub 同步状态）

```swift
struct SidebarView: View {
    @StateObject private var viewModel = SidebarViewModel()
  
    var body: some View {
        List {
            // GitHub 同步状态
            Section {
                if viewModel.isGitHubConnected {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 18))
                            .foregroundColor(.githubOrange)
                      
                        VStack(alignment: .leading, spacing: 2) {
                            Text("GitHub 同步")
                                .font(.system(size: 14, weight: .medium))
                          
                            if viewModel.isSyncing {
                                Text("正在同步...")
                                    .font(.system(size: 11))
                                    .foregroundColor(.brandBlue)
                            } else {
                                Text("上次同步: \(viewModel.lastSyncTime)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.successGreen)
                            }
                        }
                      
                        Spacer()
                      
                        if viewModel.isSyncing {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.successGreen)
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    Button {
                        viewModel.showGitHubLogin = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.triangle.2.circlepath.circle")
                                .font(.system(size: 18))
                                .foregroundColor(.githubOrange)
                          
                            Text("连接 GitHub 自动同步")
                                .font(.system(size: 14))
                                .foregroundColor(.brandBlue)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("自动备份")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
            }
          
            // WebDAV 服务器列表
            Section {
                ForEach(viewModel.webdavAccounts) { account in
                    WebDAVAccountRow(account: account)
                }
              
                Button {
                    viewModel.showAddWebDAV = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 18))
                            .foregroundColor(.brandBlue)
                      
                        Text("添加 WebDAV 服务器")
                            .font(.system(size: 14))
                            .foregroundColor(.brandBlue)
                    }
                }
                .buttonStyle(.plain)
            } header: {
                Text("云端存储")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
            }
          
            // 本地文件
            Section {
                DisclosureGroup("根目录", isExpanded: $viewModel.isLocalExpanded) {
                    ForEach(viewModel.localFiles) { file in
                        LocalFileRow(file: file)
                    }
                }
            } header: {
                Text("本地文件")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
        .listStyle(.sidebar)
        .frame(width: 280)
        .background(Color.sidebarBackground)
        .sheet(isPresented: $viewModel.showGitHubLogin) {
            GitHubLoginView()
        }
        .sheet(isPresented: $viewModel.showAddWebDAV) {
            AddWebDAVView()
        }
    }
}
```

#### 3.4.2 GitHub 登录界面

```swift
struct GitHubLoginView: View {
    @Environment(\.dismiss) var dismiss
    @State private var isAuthenticating = false
    @State private var errorMessage: String?
  
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // GitHub Logo
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 80))
                    .foregroundColor(.githubOrange)
              
                VStack(spacing: 12) {
                    Text("连接 GitHub")
                        .font(.title.bold())
                  
                    Text("自动将打开的文件同步到 GitHub 私有仓库")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
              
                VStack(spacing: 16) {
                    InfoRow(
                        icon: "lock.shield",
                        title: "隐私保护",
                        description: "使用私有仓库，仅你可见"
                    )
                  
                    InfoRow(
                        icon: "arrow.clockwise",
                        title: "自动同步",
                        description: "打开文件时自动提交"
                    )
                  
                    InfoRow(
                        icon: "iphone.and.ipad",
                        title: "跨设备访问",
                        description: "在任何设备 Clone 下来"
                    )
                }
                .padding(.horizontal)
              
                Spacer()
              
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.dangerRed)
                        .padding(.horizontal)
                }
              
                Button {
                    authenticateWithGitHub()
                } label: {
                    HStack {
                        if isAuthenticating {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        }
                      
                        Text(isAuthenticating ? "正在授权..." : "使用 GitHub 登录")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.brandBlue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(isAuthenticating)
                .padding(.horizontal)
              
                Button("稍后配置") {
                    dismiss()
                }
                .foregroundColor(.secondary)
            }
            .padding(.vertical, 32)
            .navigationTitle("GitHub 同步")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }
  
    private func authenticateWithGitHub() {
        isAuthenticating = true
        errorMessage = nil
      
        Task {
            do {
                try await GitHubService.shared.authenticate()
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isAuthenticating = false
                }
            }
        }
    }
}

struct InfoRow: View {
    let icon: String
    let title: String
    let description: String
  
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.brandBlue)
                .frame(width: 40)
          
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
              
                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
          
            Spacer()
        }
    }
}
```

#### 3.4.3 设置面板（简化版）

```swift
struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = SettingsViewModel()
  
    var body: some View {
        NavigationStack {
            List {
                // AI 配置
                Section {
                    NavigationLink {
                        AIConfigView()
                    } label: {
                        SettingRow(
                            icon: "cpu",
                            iconColor: .brandBlue,
                            title: "AI 模型配置",
                            subtitle: viewModel.isAIConfigured ? "已配置 API Key" : "未配置"
                        )
                    }
                } header: {
                    Text("AI 功能")
                }
              
                // GitHub 同步
                Section {
                    NavigationLink {
                        GitHubSyncSettingsView()
                    } label: {
                        SettingRow(
                            icon: "arrow.triangle.branch",
                            iconColor: .githubOrange,
                            title: "GitHub 同步",
                            subtitle: viewModel.isGitHubConnected ? "已连接" : "未连接"
                        )
                    }
                } header: {
                    Text("自动备份")
                }
              
                // WebDAV 管理
                Section {
                    NavigationLink {
                        WebDAVManagementView()
                    } label: {
                        SettingRow(
                            icon: "externaldrive.badge.wifi",
                            iconColor: .webdavPurple,
                            title: "WebDAV 服务器",
                            subtitle: "\(viewModel.webdavAccountCount) 个账户"
                        )
                    }
                } header: {
                    Text("云端存储")
                }
              
                // 通用设置
                Section {
                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        SettingRow(
                            icon: "paintbrush",
                            iconColor: .orange,
                            title: "通用与外观",
                            subtitle: "主题、字体、界面布局"
                        )
                    }
                  
                    NavigationLink {
                        BrowserSettingsView()
                    } label: {
                        SettingRow(
                            icon: "globe",
                            iconColor: .blue,
                            title: "浏览器",
                            subtitle: "内置浏览器设置"
                        )
                    }
                } header: {
                    Text("通用")
                }
              
                // LaTeX（可选）
                Section {
                    NavigationLink {
                        LaTeXSettingsView()
                    } label: {
                        SettingRow(
                            icon: "function",
                            iconColor: .green,
                            title: "LaTeX 环境",
                            subtitle: "配置 TeX 编译器"
                        )
                    }
                } header: {
                    Text("高级工具")
                }
              
                // 存储管理
                Section {
                    NavigationLink {
                        StorageSettingsView()
                    } label: {
                        SettingRow(
                            icon: "externaldrive",
                            iconColor: .blue,
                            title: "存储与缓存",
                            subtitle: viewModel.cacheSize
                        )
                    }
                } header: {
                    Text("存储")
                }
              
                // 关于
                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        SettingRow(
                            icon: "info.circle",
                            iconColor: .gray,
                            title: "关于",
                            subtitle: "版本 \(viewModel.appVersion)"
                        )
                    }
                  
                    Link(destination: URL(string: "https://github.com/yourusername/HappaUniclone")!) {
                        SettingRow(
                            icon: "arrow.up.forward.app",
                            iconColor: .blue,
                            title: "GitHub 仓库",
                            subtitle: "查看源代码、报告问题"
                        )
                    }
                } header: {
                    Text("其他")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct SettingRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
  
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(iconColor)
                .frame(width: 32, height: 32)
          
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
              
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
          
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
```

---

## 4. 技术架构设计

### 4.1 整体架构图

```
┌─────────────────────────────────────────────────────────┐
│                     SwiftUI Views                        │
│  (LibraryView, ReaderView, SettingsView, AIView)        │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│                   ViewModels (MVVM)                      │
│  (LibraryViewModel, ReaderViewModel, AIViewModel,        │
│   WebDAVViewModel, GitHubViewModel)                      │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│                  Business Logic Layer                    │
│  ┌──────────────┬──────────────┬────────────────────┐  │
│  │ FileService  │ PDFService   │ MarkdownService    │  │
│  │ AIService    │ WebDAVService│ GitHubService      │  │
│  │ LaTeXService │ SyncService  │ CacheManager       │  │
│  └──────────────┴──────────────┴────────────────────┘  │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│                   Data Layer                             │
│  ┌────────────────┬────────────────┬─────────────────┐ │
│  │ SwiftData      │ FileManager    │ UserDefaults    │ │
│  │ Keychain       │ LibGit2        │ Cache Storage   │ │
│  └────────────────┴────────────────┴─────────────────┘ │
└──────────────────────────────────────────────────────────┘
```

### 4.2 项目文件结构

```
HappaUni/
├── HappaUniApp.swift
├── Info.plist
├── PrivacyInfo.xcprivacy
│
├── Core/
│   ├── Models/
│   │   ├── Document.swift
│   │   ├── Folder.swift
│   │   ├── WebDAVAccount.swift
│   │   ├── WebDAVFile.swift
│   │   ├── GitHubConfig.swift
│   │   ├── AIMessage.swift
│   │   └── Settings.swift
│   │
│   ├── Services/
│   │   ├── FileService.swift
│   │   ├── PDFService.swift
│   │   ├── MarkdownService.swift
│   │   ├── EPUBService.swift
│   │   ├── AIService.swift
│   │   ├── WebDAVService.swift
│   │   ├── GitHubService.swift
│   │   ├── SyncService.swift
│   │   ├── LaTeXService.swift
│   │   └── CacheManager.swift
│   │
│   ├── Utilities/
│   │   ├── Extensions/
│   │   │   ├── View+Extensions.swift
│   │   │   ├── Color+Extensions.swift
│   │   │   ├── String+Extensions.swift
│   │   │   └── Date+Extensions.swift
│   │   ├── Constants.swift
│   │   ├── Logger.swift
│   │   └── KeychainHelper.swift
│   │
│   └── Networking/
│       ├── APIClient.swift
│       ├── OpenAIAPI.swift
│       ├── GitHubAPI.swift
│       ├── WebDAVClient.swift
│       └── NetworkError.swift
│
├── Features/
│   ├── Library/
│   │   ├── Views/
│   │   │   ├── LibraryView.swift
│   │   │   ├── SidebarView.swift
│   │   │   ├── WebDAVAccountRow.swift
│   │   │   ├── LocalFileRow.swift
│   │   │   ├── AddWebDAVView.swift
│   │   │   └── GitHubStatusView.swift
│   │   └── ViewModels/
│   │       ├── LibraryViewModel.swift
│   │       └── WebDAVViewModel.swift
│   │
│   ├── Reader/
│   │   ├── Views/
│   │   │   ├── PDFReaderView.swift
│   │   │   ├── MarkdownReaderView.swift
│   │   │   └── EPUBReaderView.swift
│   │   └── ViewModels/
│   │       └── ReaderViewModel.swift
│   │
│   ├── AI/
│   │   ├── Views/
│   │   │   ├── AIChatView.swift
│   │   │   ├── AIConfigView.swift
│   │   │   └── MessageBubbleView.swift
│   │   └── ViewModels/
│   │       └── AIViewModel.swift
│   │
│   ├── GitHub/
│   │   ├── Views/
│   │   │   ├── GitHubLoginView.swift
│   │   │   ├── GitHubSyncSettingsView.swift
│   │   │   └── GitHubHistoryView.swift
│   │   └── ViewModels/
│   │       └── GitHubViewModel.swift
│   │
│   ├── Settings/
│   │   ├── Views/
│   │   │   ├── SettingsView.swift
│   │   │   ├── AIConfigView.swift
│   │   │   ├── WebDAVManagementView.swift
│   │   │   ├── GitHubSyncSettingsView.swift
│   │   │   ├── AppearanceSettingsView.swift
│   │   │   ├── BrowserSettingsView.swift
│   │   │   ├── StorageSettingsView.swift
│   │   │   └── AboutView.swift
│   │   └── ViewModels/
│   │       └── SettingsViewModel.swift
│   │
│   └── LaTeX/
│       ├── Views/
│       │   ├── LaTeXEditorView.swift
│       │   └── LaTeXSettingsView.swift
│       └── ViewModels/
│           └── LaTeXViewModel.swift
│
├── Resources/
│   ├── Assets.xcassets/
│   ├── Localizable/
│   └── Fonts/
│
└── Tests/
```

### 4.3 核心数据模型

#### GitHubConfig.swift
```swift
import Foundation
import SwiftData

@Model
final class GitHubConfig {
    var accessToken: String
    var username: String
    var repoName: String
    var isEnabled: Bool
    var lastSyncAt: Date?
    var autoSync: Bool
  
    init(
        accessToken: String,
        username: String,
        repoName: String = "HappaUni-sync",
        isEnabled: Bool = true,
        autoSync: Bool = true
    ) {
        self.accessToken = accessToken
        self.username = username
        self.repoName = repoName
        self.isEnabled = isEnabled
        self.autoSync = autoSync
    }
}
```

#### Document.swift（增强版）
```swift
import Foundation
import SwiftData

@Model
final class Document {
    @Attribute(.unique) var id: UUID
    var name: String
    var fileURL: URL
    var type: DocumentType
    var size: Int64
    var createdAt: Date
    var modifiedAt: Date
    var lastOpenedAt: Date?
    var isFavorite: Bool
    var tags: [String]
    var thumbnailData: Data?
  
    // Git 同步相关
    var isSyncedToGitHub: Bool
    var gitCommitHash: String?
    var gitLastSyncAt: Date?
  
    @Relationship(deleteRule: .nullify) var parentFolder: Folder?
  
    init(
        id: UUID = UUID(),
        name: String,
        fileURL: URL,
        type: DocumentType,
        size: Int64 = 0,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        isFavorite: Bool = false,
        tags: [String] = [],
        isSyncedToGitHub: Bool = false
    ) {
        self.id = id
        self.name = name
        self.fileURL = fileURL
        self.type = type
        self.size = size
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.isFavorite = isFavorite
        self.tags = tags
        self.isSyncedToGitHub = isSyncedToGitHub
    }
  
    enum DocumentType: String, Codable {
        case pdf, markdown, epub, image, other
    }
}
```

---

## 5. 核心模块实现

### 5.1 GitHub 服务

#### GitHubService.swift
```swift
import Foundation
import AuthenticationServices

class GitHubService: NSObject, ObservableObject {
    static let shared = GitHubService()
  
    @Published var isAuthenticated = false
    @Published var username: String?
  
    private let clientID = "YOUR_GITHUB_CLIENT_ID"
    private let clientSecret = "YOUR_GITHUB_CLIENT_SECRET"
    private let redirectURI = "HappaUniclone://oauth/github"
  
    private var accessToken: String? {
        get { KeychainHelper.shared.read(key: "github_access_token") }
        set {
            if let token = newValue {
                KeychainHelper.shared.save(key: "github_access_token", value: token)
            } else {
                KeychainHelper.shared.delete(key: "github_access_token")
            }
        }
    }
  
    // MARK: - OAuth 认证
    func authenticate() async throws {
        let authURL = URL(string: "https://github.com/login/oauth/authorize?client_id=\(clientID)&redirect_uri=\(redirectURI)&scope=repo")!
      
        // 使用 ASWebAuthenticationSession 进行 OAuth
        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "HappaUni"
        ) { [weak self] callbackURL, error in
            guard error == nil,
                  let callbackURL = callbackURL,
                  let code = URLComponents(string: callbackURL.absoluteString)?.queryItems?.first(where: { $0.name == "code" })?.value else {
                return
            }
          
            Task {
                try await self?.exchangeCodeForToken(code: code)
            }
        }
      
        session.presentationContextProvider = self
        session.start()
    }
  
    // MARK: - 交换 Token
    private func exchangeCodeForToken(code: String) async throws {
        let url = URL(string: "https://github.com/login/oauth/access_token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      
        let body: [String: String] = [
            "client_id": clientID,
            "client_secret": clientSecret,
            "code": code,
            "redirect_uri": redirectURI
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
      
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(GitHubTokenResponse.self, from: data)
      
        accessToken = response.access_token
      
        // 获取用户信息
        try await fetchUserInfo()
    }
  
    // MARK: - 获取用户信息
    private func fetchUserInfo() async throws {
        guard let token = accessToken else { return }
      
        var request = URLRequest(url: URL(string: "https://api.github.com/user")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
      
        let (data, _) = try await URLSession.shared.data(for: request)
        let user = try JSONDecoder().decode(GitHubUser.self, from: data)
      
        await MainActor.run {
            self.username = user.login
            self.isAuthenticated = true
        }
    }
  
    // MARK: - 创建私有仓库
    func createPrivateRepo(name: String = "HappaUni-sync") async throws -> String {
        guard let token = accessToken else {
            throw GitHubError.notAuthenticated
        }
      
        var request = URLRequest(url: URL(string: "https://api.github.com/user/repos")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      
        let body: [String: Any] = [
            "name": name,
            "private": true,
            "description": "HappaUni 文档自动同步仓库",
            "auto_init": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
      
        let (data, response) = try await URLSession.shared.data(for: request)
      
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubError.invalidResponse
        }
      
        // 如果仓库已存在（422），直接返回仓库名
        if httpResponse.statusCode == 422 {
            return name
        }
      
        guard (200...299).contains(httpResponse.statusCode) else {
            throw GitHubError.createRepoFailed
        }
      
        let repo = try JSONDecoder().decode(GitHubRepo.self, from: data)
        return repo.name
    }
  
    // MARK: - 提交文件到仓库
    func commitFile(
        repoName: String,
        filePath: String,
        content: Data,
        message: String
    ) async throws -> String {
        guard let token = accessToken, let username = username else {
            throw GitHubError.notAuthenticated
        }
      
        // 1. 获取文件的 SHA（如果存在）
        let getURL = URL(string: "https://api.github.com/repos/\(username)/\(repoName)/contents/\(filePath)")!
        var getRequest = URLRequest(url: getURL)
        getRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
      
        var existingSHA: String?
        if let (data, _) = try? await URLSession.shared.data(for: getRequest),
           let fileInfo = try? JSONDecoder().decode(GitHubFileInfo.self, from: data) {
            existingSHA = fileInfo.sha
        }
      
        // 2. 上传文件
        var request = URLRequest(url: getURL)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      
        var body: [String: Any] = [
            "message": message,
            "content": content.base64EncodedString()
        ]
        if let sha = existingSHA {
            body["sha"] = sha
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
      
        let (data, response) = try await URLSession.shared.data(for: request)
      
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw GitHubError.commitFailed
        }
      
        let commitResponse = try JSONDecoder().decode(GitHubCommitResponse.self, from: data)
        return commitResponse.commit.sha
    }
  
    // MARK: - Clone 仓库（下载所有文件）
    func cloneRepo(repoName: String) async throws -> [GitHubFileInfo] {
        guard let token = accessToken, let username = username else {
            throw GitHubError.notAuthenticated
        }
      
        let url = URL(string: "https://api.github.com/repos/\(username)/\(repoName)/contents/")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
      
        let (data, _) = try await URLSession.shared.data(for: request)
        let files = try JSONDecoder().decode([GitHubFileInfo].self, from: data)
      
        return files
    }
  
    // MARK: - 下载文件
    func downloadFile(downloadURL: String) async throws -> Data {
        guard let token = accessToken else {
            throw GitHubError.notAuthenticated
        }
      
        var request = URLRequest(url: URL(string: downloadURL)!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
      
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }
  
    enum GitHubError: Error, LocalizedError {
        case notAuthenticated
        case invalidResponse
        case createRepoFailed
        case commitFailed
      
        var errorDescription: String? {
            switch self {
            case .notAuthenticated: return "未登录 GitHub"
            case .invalidResponse: return "无效的服务器响应"
            case .createRepoFailed: return "创建仓库失败"
            case .commitFailed: return "提交文件失败"
            }
        }
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding
extension GitHubService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return ASPresentationAnchor()
    }
}

// MARK: - GitHub API 模型
struct GitHubTokenResponse: Codable {
    let access_token: String
}

struct GitHubUser: Codable {
    let login: String
    let avatar_url: String
}

struct GitHubRepo: Codable {
    let name: String
    let full_name: String
}

struct GitHubFileInfo: Codable {
    let name: String
    let path: String
    let sha: String
    let download_url: String?
    let type: String
}

struct GitHubCommitResponse: Codable {
    let content: FileContent
    let commit: Commit
  
    struct FileContent: Codable {
        let sha: String
    }
  
    struct Commit: Codable {
        let sha: String
    }
}
```

### 5.2 自动同步服务

#### SyncService.swift
```swift
import Foundation
import SwiftData

class SyncService {
    static let shared = SyncService()
  
    private let gitHubService = GitHubService.shared
    private let fileManager = FileManager.default
  
    // MARK: - 打开文件时自动同步
    func syncFileOnOpen(document: Document) async throws {
        // 检查是否启用 GitHub 同步
        guard gitHubService.isAuthenticated else { return }
      
        // 检查是否需要同步（避免重复）
        guard !document.isSyncedToGitHub ||
              document.modifiedAt > (document.gitLastSyncAt ?? .distantPast) else {
            return
        }
      
        // 读取文件内容
        let fileData = try Data(contentsOf: document.fileURL)
      
        // 生成远程路径（使用文件 ID 避免冲突）
        let remotePath = "documents/\(document.id.uuidString)/\(document.name)"
      
        // 提交到 GitHub
        let commitSHA = try await gitHubService.commitFile(
            repoName: "HappaUni-sync",
            filePath: remotePath,
            content: fileData,
            message: "Sync: \(document.name) - \(Date().formatted())"
        )
      
        // 更新文档状态
        document.isSyncedToGitHub = true
        document.gitCommitHash = commitSHA
        document.gitLastSyncAt = Date()
    }
  
    // MARK: - Clone 仓库并恢复文件
    func cloneAndRestoreFiles() async throws -> [Document] {
        guard gitHubService.isAuthenticated else {
            throw SyncError.notAuthenticated
        }
      
        // 获取仓库中的所有文件
        let files = try await gitHubService.cloneRepo(repoName: "HappaUni-sync")
      
        var restoredDocuments: [Document] = []
      
        for file in files where file.type == "file" {
            // 只处理 documents 目录下的文件
            guard file.path.hasPrefix("documents/") else { continue }
          
            // 下载文件
            guard let downloadURL = file.download_url else { continue }
            let fileData = try await gitHubService.downloadFile(downloadURL: downloadURL)
          
            // 保存到本地
            let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let localURL = documentsDir.appendingPathComponent(file.name)
            try fileData.write(to: localURL)
          
            // 创建 Document 对象
            let document = Document(
                name: file.name,
                fileURL: localURL,
                type: detectFileType(from: file.name),
                size: Int64(fileData.count),
                isSyncedToGitHub: true
            )
            document.gitCommitHash = file.sha
            document.gitLastSyncAt = Date()
          
            restoredDocuments.append(document)
        }
      
        return restoredDocuments
    }
  
    // MARK: - 检测文件类型
    private func detectFileType(from filename: String) -> Document.DocumentType {
        let ext = (filename as NSString).pathExtension.lowercased()
      
        switch ext {
        case "pdf": return .pdf
        case "md", "markdown", "txt": return .markdown
        case "epub": return .epub
        case "jpg", "jpeg", "png", "gif", "heic": return .image
        default: return .other
        }
    }
  
    enum SyncError: Error, LocalizedError {
        case notAuthenticated
      
        var errorDescription: String? {
            switch self {
            case .notAuthenticated: return "未登录 GitHub"
            }
        }
    }
}
```

### 5.3 WebDAV 服务（保持原实现）

#### WebDAVService.swift
```swift
import Foundation

class WebDAVService {
    static let shared = WebDAVService()
  
    private let session: URLSession
  
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }
  
    // MARK: - 测试连接
    func testConnection(url: String, username: String, password: String) async throws {
        let baseURL = URL(string: url)!
        var request = URLRequest(url: baseURL)
        request.httpMethod = "PROPFIND"
        request.setValue("0", forHTTPHeaderField: "Depth")
        request.addBasicAuth(username: username, password: password)
      
        let (_, response) = try await session.data(for: request)
      
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw WebDAVError.connectionFailed
        }
    }
  
    // MARK: - 列出目录
    func listDirectory(
        account: WebDAVAccount,
        path: String = "/"
    ) async throws -> [WebDAVFile] {
        let url = URL(string: account.url)!.appendingPathComponent(path)
      
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.addBasicAuth(username: account.username, password: account.password)
      
        let propfindBody = """
        <?xml version="1.0" encoding="utf-8"?>
        <D:propfind xmlns:D="DAV:">
            <D:prop>
                <D:displayname/>
                <D:getcontentlength/>
                <D:getlastmodified/>
                <D:resourcetype/>
                <D:getetag/>
            </D:prop>
        </D:propfind>
        """
        request.httpBody = propfindBody.data(using: .utf8)
        request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
      
        let (data, response) = try await session.data(for: request)
      
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw WebDAVError.listDirectoryFailed
        }
      
        let files = try parseWebDAVResponse(data: data, basePath: path)
        return files
    }
  
    // MARK: - 下载文件
    func downloadFile(
        account: WebDAVAccount,
        file: WebDAVFile,
        to localURL: URL
    ) async throws {
        let remoteURL = URL(string: account.url)!.appendingPathComponent(file.path)
      
        var request = URLRequest(url: remoteURL)
        request.httpMethod = "GET"
        request.addBasicAuth(username: account.username, password: account.password)
      
        let (tempURL, response) = try await session.download(for: request)
      
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw WebDAVError.downloadFailed
        }
      
        try FileManager.default.moveItem(at: tempURL, to: localURL)
    }
  
    // MARK: - 上传文件
    func uploadFile(
        account: WebDAVAccount,
        localURL: URL,
        to remotePath: String
    ) async throws {
        let remoteURL = URL(string: account.url)!.appendingPathComponent(remotePath)
      
        var request = URLRequest(url: remoteURL)
        request.httpMethod = "PUT"
        request.addBasicAuth(username: account.username, password: account.password)
      
        let fileData = try Data(contentsOf: localURL)
      
        let (_, response) = try await session.upload(for: request, from: fileData)
      
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw WebDAVError.uploadFailed
        }
    }
  
    // MARK: - 删除文件
    func deleteFile(
        account: WebDAVAccount,
        path: String
    ) async throws {
        let url = URL(string: account.url)!.appendingPathComponent(path)
      
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.addBasicAuth(username: account.username, password: account.password)
      
        let (_, response) = try await session.data(for: request)
      
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw WebDAVError.deleteFailed
        }
    }
  
    // MARK: - 创建目录
    func createDirectory(
        account: WebDAVAccount,
        path: String
    ) async throws {
        let url = URL(string: account.url)!.appendingPathComponent(path)
      
        var request = URLRequest(url: url)
        request.httpMethod = "MKCOL"
        request.addBasicAuth(username: account.username, password: account.password)
      
        let (_, response) = try await session.data(for: request)
      
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw WebDAVError.createDirectoryFailed
        }
    }
  
    // MARK: - 解析响应
    private func parseWebDAVResponse(data: Data, basePath: String) throws -> [WebDAVFile] {
        let parser = WebDAVXMLParser()
        return try parser.parse(data: data, basePath: basePath)
    }
  
    enum WebDAVError: Error, LocalizedError {
        case connectionFailed
        case listDirectoryFailed
        case downloadFailed
        case uploadFailed
        case deleteFailed
        case createDirectoryFailed
      
        var errorDescription: String? {
            switch self {
            case .connectionFailed: return "无法连接到 WebDAV 服务器"
            case .listDirectoryFailed: return "无法列出目录内容"
            case .downloadFailed: return "下载文件失败"
            case .uploadFailed: return "上传文件失败"
            case .deleteFailed: return "删除文件失败"
            case .createDirectoryFailed: return "创建目录失败"
            }
        }
    }
}

extension URLRequest {
    mutating func addBasicAuth(username: String, password: String) {
        let credentials = "\(username):\(password)"
        if let credentialsData = credentials.data(using: .utf8) {
            let base64Credentials = credentialsData.base64EncodedString()
            setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        }
    }
}
```

---

## 6. 开发路线图

### Phase 1: 基础框架（月 1-2）

#### 月 1: 核心阅读功能
**Week 1-2: 项目初始化**
```

"创建一个 iOS 17+ SwiftUI 项目，实现以下功能：
1. 使用 NavigationSplitView 构建三栏布局
2. 左侧边栏显示文件列表（使用 List）
3. 中间/右侧区域显示欢迎页面
4. 使用 SwiftData 作为数据持久化层
5. 实现暗色模式（系统颜色 #000000, #1C1C1E, #2C2C2E）

请提供完整的项目结构和代码。"
```

**Week 3-4: PDF 阅读器**
```

"在现有项目基础上，实现 PDF 阅读器：
1. 使用 PDFKit 框架
2. 通过 UIViewRepresentable 桥接 PDFView
3. 实现基础功能：翻页、缩放、搜索
4. 添加工具栏（上一页、下一页、页码显示、目录按钮）
5. 生成 PDF 缩略图（200x280pt）

请提供 PDFReaderView.swift 和 PDFService.swift 的完整代码。"
```

#### 月 2: Markdown 与文件管理
**Week 5-6: Markdown 渲染**
```

"实现 Markdown 渲染功能：
1. 集成 Down 库（Swift Package Manager）
2. 实现 MarkdownReaderView，显示渲染后的内容
3. 添加自定义 CSS 样式（暗色主题，字体 15pt，行高 1.6）
4. 集成 Highlightr 库实现代码高亮
5. 支持 LaTeX 公式渲染（可选）

请提供完整代码和 Package.swift 配置。"
```

**Week 7-8: 文件导入与管理**
```

"实现文件管理功能：
1. 使用 UIDocumentPickerViewController 导入文件
2. 实现 FileService.swift（文件复制、删除、类型检测）
3. 实现 SwiftData 模型（Document, Folder）
4. 左侧边栏显示本地文件树（支持展开/折叠）
5. 实现文件搜索功能

请提供完整代码，包括 FileService.swift 和 LibraryView.swift。"
```

**里程碑**: 基础文档阅读功能完成

---

### Phase 2: WebDAV 集成（月 3-4）

#### 月 3: WebDAV 客户端
**Week 9-10: WebDAV 协议实现**
```

"实现 WebDAV 客户端：
1. 使用 URLSession 实现 WebDAV 方法（PROPFIND, GET, PUT, DELETE, MKCOL）
2. 实现 Basic Authentication
3. 解析 XML 响应（使用 XMLParser）
4. 实现 WebDAVService.swift 和 WebDAVXMLParser.swift
5. 支持测试连接功能

请提供完整代码，包括错误处理。"
```

**Week 11-12: WebDAV UI**
```

"实现 WebDAV 账户管理 UI：
1. 添加 WebDAV 服务器界面（服务器名称、地址、用户名、密码）
2. 常用服务预设（坚果云、Nextcloud）
3. 使用 Keychain 安全存储密码
4. 实现连接测试和错误提示
5. 左侧边栏显示多个 WebDAV 账户

请提供 AddWebDAVView.swift 和 WebDAVViewModel.swift 的完整代码。"
```

#### 月 4: 文件同步
**Week 13-14: 下载与缓存**
```

"实现 WebDAV 文件缓存机制：
1. 创建 WebDAVCacheManager.swift
2. 实现文件下载并缓存到本地
3. 显示下载进度（使用 Progress）
4. 实现离线访问已缓存的文件
5. 计算缓存大小并提供清理功能

请提供完整代码。"
```

**Week 15-16: 上传与同步**
```

"实现 WebDAV 文件上传：
1. 实现文件上传队列
2. 支持后台上传
3. 显示上传进度
4. 处理网络中断和重试
5. 实现冲突检测（etag 比对）

请提供完整代码，包括 UploadQueueManager.swift。"
```

**里程碑**: WebDAV 功能完成

---

### Phase 3: GitHub 同步（月 5）

#### 月 5: Git 自动同步
**Week 17-18: GitHub OAuth**
```

"实现 GitHub OAuth 认证：
1. 使用 ASWebAuthenticationSession 进行 OAuth 登录
2. 交换 code 获取 access_token
3. 使用 Keychain 存储 token
4. 获取用户信息（username）
5. 创建 GitHubService.swift 和 GitHubLoginView.swift

请提供完整代码，包括 OAuth 流程和 UI。"
```

**Week 19-20: 自动提交文件**
```

"实现文件自动同步到 GitHub：
1. 当用户打开文件时，自动提交到 GitHub 私有仓库
2. 使用 GitHub API 上传文件（PUT /repos/{owner}/{repo}/contents/{path}）
3. 处理文件冲突（先获取 SHA，再更新）
4. 实现 SyncService.swift 和 syncFileOnOpen() 方法
5. 在左侧边栏显示同步状态（已同步/同步中/失败）

请提供完整代码，包括 GitHub API 调用。"
```

**Week 21-22: Clone 仓库**
```

"实现从 GitHub Clone 文件：
1. 获取仓库中所有文件列表（GET /repos/{owner}/{repo}/contents/）
2. 下载文件并保存到本地
3. 创建对应的 Document 对象并保存到 SwiftData
4. 显示恢复进度（共 X 个文件，已恢复 Y 个）
5. 实现 cloneAndRestoreFiles() 方法

请提供完整代码，包括进度显示 UI。"
```

**里程碑**: GitHub 自动同步功能完成

---

### Phase 4: AI 集成（月 6）

#### 月 6: OpenAI API
**Week 23-24: AI 对话**
```

"实现 OpenAI API 集成：
1. 创建 AIService.swift，封装 Chat Completions API
2. 实现 API Key 管理（Keychain 存储）
3. 支持自定义 Base URL（用于第三方代理）
4. 提取文档上下文（PDF 文本、Markdown 内容）
5. 实现对话 UI（AIChatView.swift，类似 iMessage 气泡）

请提供完整代码，包括网络请求和错误处理。"
```

**Week 25-26: AI 配置与优化**
```

"优化 AI 功能：
1. 实现模型选择（GPT-4, GPT-3.5, GPT-4-turbo）
2. 实现对话历史记录（保存到 SwiftData）
3. 添加 Token 使用统计
4. 实现流式响应（Server-Sent Events）
5. 优化上下文提取（智能截断，保留关键段落）

请提供完整代码，包括 AIViewModel.swift。"
```

**里程碑**: AI 功能完成

---

### Phase 5: EPUB 与高级功能（月 7-8）

#### 月 7: EPUB 阅读器
**Week 27-30: EPUB 支持**

```

"实现 EPUB 阅读器：
1. 研究 EPUB 格式（ZIP 压缩的 HTML/XML）
2. 解压 EPUB 文件并提取内容
3. 解析 OPF 文件获取章节列表
4