# NapCat-Mac-Installer

<p align="center">
  <img src="https://img.shields.io/badge/Language-Swift-orange?logo=swift" alt="Swift">
  <img src="https://img.shields.io/badge/Platform-macOS%2012%2B-blue?logo=apple" alt="macOS">
  <img src="https://img.shields.io/badge/Arch-aarch64-lightgrey?logo=arm" alt="aarch64">
  <img src="https://img.shields.io/badge/Dependency-ZIPFoundation-orange?logo=data:image/svg%2Bxml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCIgZmlsbD0ibm9uZSIgc3Ryb2tlPSJjdXJyZW50Q29sb3IiIHN0cm9rZS13aWR0aD0iMiIgc3Ryb2tlLWxpbmVjYXA9InJvdW5kIiBzdHJva2UtbGluZWpvaW49InJvdW5kIj48cGF0aCBkPSJNMjEgMTYuNWExIDEgMCAwIDEtLjUuODdsLTggNC41YTEgMSAwIDAgMS0xIDBsLTgtNC41QTEgMSAwIDAgMSAzIDE2LjV2LTlhMSAxIDAgMCAxIC41LS44N2w4LTQuNWExIDEgMCAwIDEgMSAwbDggNC41QTEgMSAwIDAgMSAyMSA3LjVaIi8+PHBvbHlsaW5lIHBvaW50cz0iMyA3LjUgMTIgMTIgMjEgNy41Ii8+PGxpbmUgeDE9IjEyIiB5MT0iMTIiIHgyPSIxMiIgeTI9IjIxIi8+PHBvbHlsaW5lIHBvaW50cz0iMyA3LjUgMyAxNi41IDEyIDIxIiBvcGFjaXR5PSIwLjMiLz48L3N2Zz4=" alt="ZIPFoundation">
</p>

## 功能特性

- **一键安装/更新/卸载** - 快速安装、更新或移除 NapCat
- **智能代理选择** - 内置 40 个 GitHub 代理服务器，自动测速选择最快的可用代理
- **实时安装进度** - 显示下载进度、解压状态等详细日志，支持文本复制
- **版本检测** - 自动检测本地和远程版本，提示更新
- **QQ 修改** - 自动修改 package.json ，快速启动原版QQ/NapCat
- **WebUI 快捷入口** - 安装完成后可直接打开 NapCat WebUI（仅在 NapCat 入口时可用）
- **下载完整性校验** - 从 GitHub API 获取 SHA-256 digest，下载后验证文件完整性，防止代理投毒

## 使用方法

1. **打开应用** - 启动 NapCat-Mac-Installer (NapCat安装器.app)
2. **选择代理**（可选）- 默认为「自动检测」，也可手动选择特定代理
3. **点击安装** - 等待下载和安装完成
4. **修改 QQ** - 自动修改
5. **启动 NapCat** - 自行选择原版QQ/NapCat

注意：在“系统设置-隐私与安全性-App管理”中添加该程序才能完成自动切换程序入口！

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

## 技术原理

NapCat-Mac-Installer 的核心机制是修改 QQ（Electron 应用）的入口配置来实现 NapCat 的加载。

### 沙箱限制与突破

macOS 上的 QQ 受到多层沙箱限制，安装器需要逐一突破：

| 限制 | 说明 | 突破方式 |
|------|------|----------|
| **macOS App Sandbox** | QQ 只能读写自己的容器目录 `~/Library/Containers/com.tencent.qq/Data/` | NapCat 文件和加载器放在容器内，QQ 运行时可以正常访问 |
| **文件系统权限** | `/Applications/QQ.app/` 普通进程无法修改其内容 | 通过 `Process` 拉起 `sudo -S`，用户密码通过管道标准输入传递，临时获取与用户同级的 root 权限来修改 `package.json`。常规方法（如 `chmod` 提权、Authorization Services）无法直接修改其他应用的 bundle 内容 |
| **Hardened Runtime** | QQ 的代码签名禁止加载未签名库/脚本 | 安装器启用 `disable-library-validation` 等 entitlement，允许加载 NapCat |
| **Chromium Sandbox** | Electron 沙箱限制子进程行为 | NapCat 启动时传入 `--no-sandbox` 参数 |

简单来说：**NapCat 文件放在 QQ 的沙箱容器内（QQ 能读到），但 QQ 的入口配置文件在 app bundle 内（需要 root 权限才能改），安装器借助 `sudo` 跨越这个权限鸿沟。**

### 什么是 `package.json`？

QQ 是一个基于 Electron 的桌面应用，其本质是一个 Node.js 运行时。`package.json` 是 Electron/Node.js 项目的入口配置文件，其中的 `main` 字段指定了应用启动时首先执行的 JavaScript 文件。

### `package.json` 文件位置

```
/Applications/QQ.app/Contents/Resources/app/package.json
```

### NapCat 安装位置

```
~/Library/Containers/com.tencent.qq/Data/Documents/napcat/
  ├── napcat.mjs            # NapCat 主模块
  ├── package.json          # NapCat 版本信息
  └── ...                   # 配置文件等
```

同时会在同目录下生成中转加载器：

```
~/Library/Containers/com.tencent.qq/Data/Documents/loadNapCat.js
```

### 注入流程

1. **备份** - 将原始的 `package.json` 复制为 `package.json.bak`
2. **创建加载器** - 在用户目录下生成 `loadNapCat.js`，作为中转脚本
3. **修改入口** - 将 `package.json` 的 `main` 字段从原来的路径改为指向 `loadNapCat.js`

### `loadNapCat.js` 工作原理

```
┌─────────────────────────────────────────────────┐
│                    QQ 启动！                     │
│       package.json->main->loadNapCat.js         │
├─────────────────────────────────────────────────┤
│  loadNapCat.js 判断启动参数:                      │
│  --no-sandbox 存在？                             │
│      ✅ -> 导入 napcat.mjs                       │
│      ❌ -> 导入原版启动器 --不建议该方法启动原版      │
└─────────────────────────────────────────────────┘
```

- **启动 NapCat** → 传入 `--no-sandbox` 参数 → `loadNapCat.js` 加载 `napcat.mjs`
- **启动 原版QQ** → 无特殊参数 → `loadNapCat.js` 加载原始的 QQ 启动器

这种方式使得只需修改一次 `package.json`，通过命令行参数即可切换 NapCat/原版 QQ，无需反复修改配置文件。

## 更新日志

- [x] **下载完整性校验** - SHA-256 验证，API 不可达时拒绝下载
- [x] **合并 API 调用** - `fetchReleaseInfo()` 一次请求获取版本和校验和
- [x] **API 前置检查** - 下载前必须连通 GitHub API，否则中断安装
- [x] **容器路径修复** - `NSHomeDirectory()` 替代 `NSUserName()`，适配非常规 home 目录
- [x] **WebUI 条件显示** - 仅在 NapCat 入口时显示 WebUI 按钮
- [x] **安装按钮隐藏** - 安装中按钮隐藏，完成后弹窗通知结果
- [x] **日志持久化** - 安装日志需用户主动关闭
- [x] **本地化** - 中英文双语
- [x] **README 重写** - 添加徽章、技术原理（沙箱突破、注入流程、路径说明）
- [x] **安全修复** - TLS 校验、密码管道传输、shell 注入消除、entitlements 补全、`NSAllowsArbitraryLoads` 移除、弃用 API 迁移
- [x] **稳定性修复** - 自引用编译错误、nil 写入 JSON、后台线程、Task 线程安全
- [ ] **清理 NapCat 数据** - '~/Library/Containers/com.tencent.qq/Data/Library/Application Support/QQ/NapCat'

## 相关链接

- [NapCatQQ](https://github.com/NapNeko/NapCatQQ) - NapCat 官方仓库
