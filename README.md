# NapCat-Mac-Installer

macOS 12+ 的 NapCat 安装和更新工具，支持 Intel / Apple Silicon。

## 使用

1. 将 QQ 安装到 `/Applications/QQ.app`。
2. 下载并打开 [安装器](https://github.com/NapNeko/NapCat-Mac-Installer/releases/latest)，选择 NapCat 版本和下载方式，点击安装。
3. 按提示备份并修改 QQ 入口，选择「切换程序入口 NapCat」，然后启动。
4. 恢复原版时选择「切换程序入口 原版 QQ」。

入口修改被系统拒绝时，在「系统设置 → 隐私与安全性 → App 管理」中允许安装器管理 QQ。

配置和插件位于 `~/Library/Containers/com.tencent.qq/Data/Documents/napcat`，更新时保留。

## 构建

使用 Xcode 打开 `NapCatInstaller.xcodeproj`，选择 `NapCatInstaller` scheme 构建。CI 提供 universal 安装包。

[使用文档](https://napneko.github.io/guide/boot/Shell#macos)
