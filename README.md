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

![启动管理面板：NapCat 与原版 QQ 同时运行（示例数据）](docs/images/readme-dual-instance.png)

切换到 NapCat 入口后，启动管理面板每 2 秒读取一次实际进程，显示 NapCat 与原版 QQ 的运行状态、PID 和窗口状态。两者可以同时运行，互不结束对方：

| 按钮 | 行为 |
| --- | --- |
| 启动 NapCat | 在新的终端窗口中以 `--no-sandbox` 启动；NapCat 已在运行时不重复启动，不会结束原版 QQ |
| 启动 / 显示 原版QQ | 以新实例（`open -n`）打开原版 QQ 图形界面；已有原版实例时激活它，不重复创建 |
| 停止 | 确认后只结束所选的那个实例：先请求正常退出，10 秒无响应才发送 SIGTERM，不使用 SIGKILL |

使用方法：

1. 按上面的步骤安装 NapCat，并选择「切换程序入口 NapCat」。
2. 点击「启动 NapCat」，按 NapCat 的提示登录机器人账号。
3. 点击「启动 原版QQ」，在图形界面中登录**另一个** QQ 账号。

注意事项：

- 两个实例必须使用不同的 QQ 账号。
- 两者共用 `~/Library/Containers/com.tencent.qq/Data`（包括 `global/nt_db/login.db` 和 mmkv 数据）。测试中没有发现冲突，但长时间同时运行的稳定性尚未充分验证。
- 面板提示「加载器为旧版」时点击「更新加载器」，只会替换 `loadNapCat.js`，已运行的 QQ 不受影响；自定义的加载器会先备份再替换。
- QQ 热更新生成新版本后，「启动 NapCat」会自动把新热更新包的入口指向 NapCat。

![旧版加载器提示（示例数据）](docs/images/readme-legacy-loader.png)

### 原理

QQ 热更新后，原生启动程序会从 `versions/<版本>/QQUpdate.app` 加载新的 Electron 运行时（例如 7.0.2-53644 使用 Electron 40.0.0）。旧版 `loadNapCat.js` 的原版分支固定加载基础包 `QQ.app` 中为旧运行时（Electron 37.1.0）构建的启动器，结果 QQ 进程存在却不创建任何窗口。新加载器读取各候选包中 `QQNT.framework` 的版本，选择与当前运行时 `process.versions.electron` 一致的启动器；找不到匹配时明确报错，不会回退到不兼容的启动器。详见 [docs/dual-instance.md](docs/dual-instance.md)。

### 测试状态

- 加载器修复已在真实环境中验证（macOS 15.7.5、Apple Silicon、QQ 6.9.96 + 热更新 7.0.2-53644、NapCat 4.18.41）：NapCat 机器人保持在线的同时，原版 QQ 正常显示窗口并登录另一个账号。
- GitHub Actions 上使用 Xcode 16.4 的 Release 构建成功（universal，0 个错误，无编译警告）。
- 启动管理面板的界面与按钮逻辑通过 mock 进程测试（26 项）；启动、停止按钮尚未针对真实 QQ 进程进行端到端测试。

### Running NapCat and the native QQ client together

After switching the entry point to NapCat, the launch panel polls the process table every 2 seconds and shows whether NapCat and the native QQ client are running, with PID and window state. Either one can be started without stopping the other:

- **Start NapCat** opens a new Terminal window with `--no-sandbox`. It does nothing if NapCat is already running and never stops the native client.
- **Start / Show native QQ** opens a new native instance with `open -n`, or activates the existing one instead of creating more.
- **Stop** ends only the selected instance after confirmation: a normal quit request first, SIGTERM after 10 seconds, never SIGKILL.

Log into a **different** QQ account in the native client. Both instances share the QQ container, including `global/nt_db/login.db` and the mmkv store; no conflict was seen in testing, but long-running concurrent use is not proven.

Why the native client used to show no window: after a QQ hot update the native stub runs the Electron runtime from `versions/<version>/QQUpdate.app` (Electron 40.0.0 for 7.0.2-53644), while the previous loader always required the launcher of the base `QQ.app`, built for Electron 37.1.0. The loader now picks the launcher whose `QQNT.framework` version matches `process.versions.electron` and throws a clear error instead of falling back to an incompatible one.

Test status: the loader fix was verified end to end on macOS 15.7.5 (Apple Silicon) with the bot online and a second account in the native client; the Xcode 16.4 Release build passes on GitHub Actions; the launch panel's start and stop buttons have so far been tested only against mock processes. Details are in [docs/dual-instance.md](docs/dual-instance.md).

## 构建

使用 Xcode 打开 `NapCatInstaller.xcodeproj`，选择 `NapCatInstaller` scheme 构建。CI 提供 universal 安装包。

[使用文档](https://napneko.github.io/guide/boot/Shell#macos)

## 许可证 / License

MIT，见 [LICENSE](LICENSE)。Copyright (c) 2024 NapNeko.
