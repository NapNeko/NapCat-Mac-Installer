# NapCat-Mac-Installer

macOS 12+ 的 NapCat 安装和更新工具，支持 Intel / Apple Silicon。

## 使用

1. 将 QQ 安装到 `/Applications/QQ.app`。
2. 下载并打开 [安装器](https://github.com/NapNeko/NapCat-Mac-Installer/releases/latest)，选择 NapCat 版本和下载方式，点击安装。
3. 按提示备份并修改 QQ 入口，选择「切换程序入口 NapCat」，然后启动。
4. 恢复原版时选择「切换程序入口 原版 QQ」。

入口修改被系统拒绝时，在「系统设置 → 隐私与安全性 → App 管理」中允许安装器管理 QQ。

配置和插件位于 `~/Library/Containers/com.tencent.qq/Data/Documents/napcat`，更新时保留。

## 同时运行 NapCat 与原版 QQ

切换到 NapCat 入口后，启动管理面板会显示 NapCat 与原版 QQ 的实际运行状态，两者可以同时运行：

- 「启动 NapCat」：NapCat 已运行时不重复启动，不会结束原版 QQ。
- 「启动 原版QQ」：以新实例打开原版 QQ 图形界面，供另一个账号登录；已有原版实例时直接激活它。
- 「停止」：只结束所选的那个实例，先请求正常退出。

QQ 热更新后加载器会自动匹配当前运行时的启动器。

### Running NapCat and the native QQ client together

After switching the entry point to NapCat, the launch panel shows the live state of NapCat and of the native QQ client and can start either one without stopping the other. Use a different QQ account in the native client. The loader picks the QQ launcher that matches the Electron runtime in use, including after QQ hot updates. See [docs/dual-instance.md](docs/dual-instance.md) for the root cause, behaviour and limitations.

## 构建

使用 Xcode 打开 `NapCatInstaller.xcodeproj`，选择 `NapCatInstaller` scheme 构建。CI 提供 universal 安装包。

[使用文档](https://napneko.github.io/guide/boot/Shell#macos)
