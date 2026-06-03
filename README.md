# NapCat-Mac-Installer

NapCat macOS 一键安装器

## 功能特性

- **一键安装/更新/卸载** - 快速安装、更新或移除 NapCat
- **智能代理选择** - 内置 40+ 个 GitHub 代理服务器，自动测速选择最快的可用代理
- **实时安装进度** - 显示下载进度、解压状态等详细日志，支持文本复制
- **版本检测** - 自动检测本地和远程版本，提示更新
- **QQ 修改** - 自动修改 package.json ，快速启动原版QQ/NapCat
- **WebUI 快捷入口** - 安装完成后可直接打开 NapCat WebUI

## 使用方法

1. **打开应用** - 启动 NapCat-Mac-Installer
2. **选择代理**（可选）- 默认为「自动检测」，也可手动选择特定代理
3. **点击安装** - 等待下载和安装完成
4. **修改 QQ** - 自动修改
5. **启动 NapCat** - 自行选择原版QQ/NapCat

注意：在“系统设置-隐私与安全性-App管理”中添加该程序才能完成自动切换程序入口！

## 技术细节

- **框架**: SwiftUI
- **依赖**: ZIPFoundation
- **网络**: 使用系统默认 TLS 证书校验，支持 40+ GitHub 代理镜像

## 项目结构

```
NapCatInstaller/
├── NapCatInstallerApp.swift    # 应用入口
├── ContentView.swift           # 主界面
├── Utils.swift                 # 核心功能
├── Localizable.xcstrings       # 本地化字符串
├── Info.plist                  # 应用配置
└── NapCatInstaller.entitlements # 沙箱授权
```

## TODO

- [x] **移除 TLS 证书绕过** - 删除自定义 URLSessionDelegate 中无条件信任所有证书的逻辑，使用系统默认 TLS 校验
- [x] **修复密码泄露风险** - `getQQPackageBak` / `setQQPackageBak` 中不再通过 shell 命令行传递密码，改为 `Process.standardInput` 管道直接写入 `sudo -S`；密码不再出现在进程参数 / 日志中
- [x] **消除 shell 注入** - 所有 sudo 操作改用 `Process` + 分离参数列表（`["sudo", "-S", "cp", src, dst]`），不再拼接 shell 命令字符串
- [x] **修复自引用编译错误** - `getQQPackageBak()` 中 `let packageURL = packageURL` 导致的遮蔽问题
- [x] **修复 `newVersion` 为 nil 时崩溃** - `getRemoteNapcat()` 返回 nil 时不再写入 `Optional` 到 JSON
- [x] **修复 `reset()` 后台线程问题** - `InstallationProgress.reset()` 切到主线程更新 `@Published` 属性
- [x] **修复 Task 线程安全** - ContentView 中安装按钮的 `Task` 添加 `@MainActor` 确保所有 UI 状态在主线程更新
- [x] **补全 Entitlements** - 添加 Hardened Runtime 必需授权（`disable-library-validation`、`allow-unsigned-executable-memory`、`allow-dyld-environment-variables`）
- [x] **移除 `NSAllowsArbitraryLoads`** - 不再全局禁用 ATS，仅通过 HTTPS 连接
- [x] **弃用 API 迁移** - `launchPath` 替换为 `executableURL`
- [ ] **下载完整性校验** - 从 GitHub Releases API 获取 NapCat.Shell.zip 的 SHA-256 digest，下载后验证文件完整性，防止代理投毒

## 相关链接

- [NapCatQQ](https://github.com/NapNeko/NapCatQQ) - NapCat 官方仓库
