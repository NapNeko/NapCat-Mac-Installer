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

注意：

## 技术细节

- **框架**: SwiftUI
- **依赖**: ZIPFoundation
- **网络**: 支持 HTTP/HTTPS 代理，自动绕过 SSL 证书验证
- **安全**: 支持各种代理服务器

## 项目结构

```
NapCatInstaller/
├── NapCatInstallerApp.swift    # 应用入口
├── ContentView.swift           # 主界面
├── Utils.swift                 # 核心功能
├── Localizable.xcstrings       # 本地化字符串
└── Info.plist                  # 应用配置
```

## 相关链接

- [NapCatQQ](https://github.com/NapNeko/NapCatQQ) - NapCat 官方仓库

## 许可证

```
MIT License

Copyright (c) 2024 NapNeko

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
