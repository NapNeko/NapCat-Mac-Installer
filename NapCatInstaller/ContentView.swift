import SwiftUI

struct ContentView: View {
    @AppStorage("GitHubProxyIndex") private var proxyIndex: Int = -1
    @State private var qqVersion = QQVersion.loading
    @State private var patchStatus = PatchStatus.loading
    @State private var napcatVersion = NapcatVersion.loading
    @State private var buttonClicked = false
    @State private var showLogs = false
    @State private var showPaths = false
    @StateObject private var installationProgress = InstallationProgress()
    
    private var proxy: GitHubProxy? {
        if proxyIndex < 0 || proxyIndex >= GitHubProxy.allProxies.count {
            return nil
        }
        return GitHubProxy.allProxies[proxyIndex]
    }

    private var showPatch: Bool {
        return napcatVersion.installed || patchStatus.patched
    }

    private var showUsage: Bool {
        return patchStatus.patched
    }

    var body: some View {
        VStack(alignment: .center, spacing: 20) {
            HStack {
                VStack(alignment: .trailing, spacing: 5) {
                    Text("QQ版本")
                    Text("NapCat版本")
                    Text("程序入口")
                }
                VStack(alignment: .leading, spacing: 5) {
                    QQVersionView(version: qqVersion)
                    NapcatVersionView(version: napcatVersion)
                    PatchStatusView(status: patchStatus)
                }
                .foregroundColor(.secondary)
            }
            Divider()
            HStack(spacing: 15) {
                Button {
                    buttonClicked.toggle()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise.circle")
                }
                NapcatInstallationButton(version: napcatVersion, status: patchStatus, proxy: proxy, showLogs: $showLogs, progress: installationProgress) {
                    buttonClicked.toggle()
                }
                Picker("代理", selection: $proxyIndex) {
                    Text("自动检测").tag(-1)
                    ForEach(Array(GitHubProxy.allProxies.enumerated()), id: \.offset) { index, proxyItem in
                        Text(proxyItem.name)
                            .tag(index)
                    }
                }
                .frame(maxWidth: 150)
            }
            if showLogs {
                NapcatLogView(progress: installationProgress)
            }
            if showPatch {
                NapcatPatchView(status: patchStatus, refreshHandler: updatePatchStatus)
            }
            if showUsage {
                NapcatUsageView()
            }
            HStack(spacing: 20) {
                if patchStatus.patched, let url = try? getWebUILink() {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("打开WebUI", systemImage: "network")
                    }
                }
                Button {
                    showPaths = true
                } label: {
                    Label("文件位置", systemImage: "folder")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .animation(.default, value: qqVersion)
        .animation(.default, value: patchStatus)
        .animation(.default, value: napcatVersion)
        .task(id: buttonClicked) {
            updateAll()
        }
        .sheet(isPresented: $showPaths) {
            NapcatPathsView()
        }
    }
    
    private func updateQQVersion() {
        do {
            guard let version = try getQQVersion() else {
                qqVersion = .missing
                return
            }
            qqVersion = .installed(version)
        } catch {
            qqVersion = .failed(error.localizedDescription)
        }
    }

    private func updateNapcatVersion() async {
        do {
            guard let local = try getLocalNapcat() else {
                napcatVersion = .missing
                return
            }
            do {
                guard let remote = try await getRemoteNapcat() else {
                    napcatVersion = .installed(local)
                    return
                }
                if local.compare(remote, options: .numeric) == .orderedAscending {
                    napcatVersion = .outdated(local, remote)
                } else {
                    napcatVersion = .latest(remote)
                }
            } catch {
                napcatVersion = .installed(local)
            }
        } catch {
            napcatVersion = .failed(error.localizedDescription)
        }
    }
    
    private func updateAll() {
        updateQQVersion()
        updatePatchStatus()
        Task { await updateNapcatVersion() }
    }

    private func updatePatchStatus() {
        do {
            guard let loader = try getAppLoader() else {
                patchStatus = .custom("")
                return
            }
            switch loader {
            case let l where PatchStatus.originalLoaders.contains(l):
                patchStatus = .original
            case napcatLoader:
                patchStatus = .napcat
            default:
                patchStatus = .custom(loader)
            }
        } catch {
            patchStatus = .failed(error.localizedDescription)
        }
    }
}

private struct QQVersionView: View {
    let version: QQVersion
    var body: some View {
        switch version {
        case .loading:
            Text(Image(systemName: "ellipsis.circle")) + Text(" 正在读取…")
        case .missing:
            Text(Image(systemName: "questionmark.circle")).foregroundColor(.yellow) + Text(" 未安装")
        case .installed(let v):
            Text(Image(systemName: "checkmark.circle")).foregroundColor(.green) + Text(" \(v)")
        case .failed(let d):
            (Text(Image(systemName: "xmark.circle")).foregroundColor(.red) + Text(" 发生错误")).help(d)
        }
    }
}

private struct NapcatVersionView: View {
    let version: NapcatVersion
    var body: some View {
        switch version {
        case .loading:
            Text(Image(systemName: "ellipsis.circle")) + Text(" 正在加载…")
        case .missing:
            Text(Image(systemName: "questionmark.circle")).foregroundColor(.yellow) + Text(" 未安装")
        case .installed(let v):
            Text(Image(systemName: "checkmark.circle")).foregroundColor(.green) + Text(" \(v)，已安装")
        case .outdated(let l, let r):
            Text(Image(systemName: "arrow.up.circle")).foregroundColor(.blue) + Text(" \(l)，可升级\(r)")
        case .latest(let v):
            Text(Image(systemName: "checkmark.circle")).foregroundColor(.green) + Text(" \(v)，已是最新")
        case .failed(let d):
            (Text(Image(systemName: "xmark.circle")).foregroundColor(.red) + Text(" 发生错误")).help(d)
        }
    }
}

private struct PatchStatusView: View {
    let status: PatchStatus
    var body: some View {
        switch status {
        case .loading:
            Text(Image(systemName: "ellipsis.circle")) + Text(" 正在读取…")
        case .original:
            Text(Image(systemName: "ellipsis.circle")).foregroundColor(.blue) + Text(" 原版QQ")
        case .napcat:
            Text(Image(systemName: "checkmark.circle")).foregroundColor(.green) + Text(" NapCat")
        case .custom(let loader):
            Text(Image(systemName: "questionmark.circle")).foregroundColor(.yellow) + Text(" 自定义 \(loader)")
        case .failed(let d):
            (Text(Image(systemName: "xmark.circle")).foregroundColor(.red) + Text(" 发生错误")).help(d)
        }
    }
}

private struct NapcatInstallationButton: View {
    let version: NapcatVersion
    let status: PatchStatus
    let proxy: GitHubProxy?
    @Binding var showLogs: Bool
    @ObservedObject var progress: InstallationProgress
    let refreshHandler: () -> Void
    @State private var loading = false
    @State private var failed = false
    @State private var showSuccessAlert = false
    @State private var installMessage = "操作完成"
    @State private var error: Error?
    var body: some View {
        Group {
            switch version {
            case .loading, .failed:
                Button {
                    fatalError("Should not be reachable")
                } label: {
                    Label("安装", systemImage: "shippingbox.circle")
                }
                .disabled(true)
            case .missing, .outdated:
                if !loading {
                    Button {
                        Task { @MainActor in
                            loading = true
                            showLogs = true
                            progress.reset()
                            progress.isInstalling = true
                            do {
                                try await installNapcat(proxy: proxy, progress: progress)
                                switch version {
                                case .missing:
                                    installMessage = "NapCat 安装成功"
                                case .outdated:
                                    installMessage = "NapCat 已更新至最新版本"
                                default:
                                    installMessage = "操作完成"
                                }
                                showSuccessAlert = true
                            } catch {
                                failed = true
                                self.error = error
                            }
                            progress.isInstalling = false
                            loading = false
                            showLogs = false
                            progress.reset()
                        }
                    } label: {
                        switch version {
                        case .missing:
                            Label("安装", systemImage: "shippingbox.circle")
                        case .outdated:
                            Label("更新", systemImage: "arrow.up.circle")
                        default:
                            fatalError("Should not be reachable")
                        }
                    }
                }
            case .installed, .latest:
                Button {
                    do {
                        try removeNapcat()
                    } catch {
                        failed = true
                        self.error = error
                    }
                    refreshHandler()
                } label: {
                    Label("卸载", systemImage: "trash.circle")
                }
                .disabled(status.patched)
                .help("请先还原再卸载")
            }
        }
        .alert("发生错误", isPresented: $failed, presenting: error) { _ in
            Button("好") {
                failed = false
                refreshHandler()
            }
        } message: { e in
            Text(e.localizedDescription)
        }
        .alert("安装结果", isPresented: $showSuccessAlert) {
            Button("好") {
                refreshHandler()
            }
        } message: {
            Text(installMessage)
        }
    }
}

private struct NapcatLogView: View {
    @ObservedObject var progress: InstallationProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                ProgressView(value: progress.progress) {
                    Text("进度: \(progress.progress.formatted(.percent))")
                }
                .progressViewStyle(.linear)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(progress.logs) { log in
                            HStack(alignment: .top, spacing: 8) {
                                Text(log.timestamp, style: .time)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 60, alignment: .leading)
                                Text(log.message)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                Spacer()
                            }
                            .id(log.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: progress.logs.count) { _ in
                    guard let last = progress.logs.last else { return }
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            .font(.system(.callout, design: .monospaced))
            .padding(.horizontal)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.selection)
            .cornerRadius(5)
        }
    }
}

private struct NapcatPatchView: View {
    let status: PatchStatus
    let refreshHandler: () -> Void
    @State private var failed = false
    @State private var error: Error?

    var body: some View {
        switch status {
        case .loading, .failed:
            EmptyView()
        case .original, .custom:
            patchButton(title: "切换程序入口「 NapCat 」", action: setQQPackageBak)
        case .napcat:
            patchButton(title: "切换程序入口「 原版 QQ 」", action: { _ = getQQPackageBak() })
        }
    }

    @ViewBuilder
    private func patchButton(title: LocalizedStringKey, action: @escaping () throws -> Void) -> some View {
        VStack(alignment: .center) {
            Button(title) {
                do {
                    try action()
                } catch {
                    failed = true
                    self.error = error
                }
                refreshHandler()
            }
            Text("注意：需要在“系统设置-隐私与安全性-App管理”中添加该程序！")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .alert("发生错误", isPresented: $failed, presenting: error) { _ in
            Button("好") { failed = false }
        } message: { e in
            Text(e.localizedDescription)
        }
    }
}

private struct NapcatUsageView: View {
    @State private var launchError: String? = nil
    @State private var showNapcatConfirm = false
    @State private var showOriginalConfirm = false

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            HStack(spacing: 20) {
                Button("🐱 启动 NapCat") {
                    prepareLaunch(mode: .napcat)
                }
                Button("🐧 启动 原版QQ") {
                    prepareLaunch(mode: .original)
                }
            }
            if let error = launchError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .alert("确认启动", isPresented: $showNapcatConfirm) {
            Button("使用终端打开") {
                launchInTerminal()
            }
            Button("复制") {
                copyCommand()
            }
            Button("取消", role: .cancel) {
            }
        } message: {
            Text(napcatCommand)
        }
        .alert("启动原版QQ", isPresented: $showOriginalConfirm) {
            Button("启动") {
                restoreAndLaunchOriginal()
            }
            Button("取消", role: .cancel) {
            }
        } message: {
            Text("将恢复 QQ 原版程序入口并启动，需要输入开机密码。")
        }
    }

    private enum LaunchMode {
        case napcat
        case original
    }

    private var napcatCommand: String {
        "'/Applications/QQ.app/Contents/MacOS/QQ' --no-sandbox"
    }

    private func getQQAppURL() -> URL? {
        let defaultPath = "/Applications/QQ.app"
        let url = URL(fileURLWithPath: defaultPath)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    private func terminateQQ() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["-9", "QQ", "QQEXDOC"]
        do {
            try process.run()
            process.waitUntilExit()
            Thread.sleep(forTimeInterval: 1.0)
        } catch {
        }
    }

    private func prepareLaunch(mode: LaunchMode) {
        guard let qqAppURL = getQQAppURL() else {
            launchError = "未找到 QQ.app，请确认已安装 QQ"
            return
        }
        let executableURL = qqAppURL.appendingPathComponent("Contents/MacOS/QQ")
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            launchError = "QQ 可执行文件不存在或不可执行"
            return
        }
        launchError = nil
        switch mode {
        case .napcat:
            showNapcatConfirm = true
        case .original:
            showOriginalConfirm = true
        }
    }

    private func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(napcatCommand, forType: .string)
    }

    private func launchInTerminal() {
        terminateQQ()
        guard let qqAppURL = getQQAppURL() else { return }
        let executableURL = qqAppURL.appendingPathComponent("Contents/MacOS/QQ")
        let path = executableURL.path
        let escapedPath = path.replacingOccurrences(of: "'", with: "'\\''")
        let flag = "--no-sandbox"
        let script = """
        tell application "Terminal"
            activate
            if (count of windows) is 0 then
                do script "'\(escapedPath)' \(flag)"
            else
                tell front window
                    do script "'\(escapedPath)' \(flag)" in selected tab
                end tell
            end if
        end tell
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        do {
            try process.run()
            launchError = nil
        } catch {
            launchError = "启动失败: \(error.localizedDescription)"
        }
    }

    private func restoreAndLaunchOriginal() {
        terminateQQ()
        let restored = getQQPackageBak()
        guard restored else { return }
        guard let qqAppURL = getQQAppURL() else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [qqAppURL.path]
        do {
            try process.run()
            launchError = nil
        } catch {
            launchError = "启动失败: \(error.localizedDescription)"
        }
    }
}

private struct NapcatPathsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("文件位置")
                    .font(.headline)
                Spacer()
                Button("完成") {
                    dismiss()
                }
            }
            PathRow(title: "QQ 入口配置", path: "/Applications/QQ.app/Contents/Resources/app/package.json", isDirectory: false)
            PathRow(title: "QQ 热更新包", path: "\(NSHomeDirectory())/Library/Containers/com.tencent.qq/Data/Library/Application Support/QQ/versions", isDirectory: true)
            PathRow(title: "NapCat 加载器", path: "\(NSHomeDirectory())/Library/Containers/com.tencent.qq/Data/Documents/loadNapCat.js", isDirectory: false)
            PathRow(title: "NapCat 安装位置", path: "\(NSHomeDirectory())/Library/Containers/com.tencent.qq/Data/Documents/napcat", isDirectory: true)
            PathRow(title: "NapCat 数据存储", path: "\(NSHomeDirectory())/Library/Containers/com.tencent.qq/Data/Library/Application Support/QQ/NapCat", isDirectory: true)
            PathRow(title: "NapCat 配置目录", path: "\(NSHomeDirectory())/Library/Containers/com.tencent.qq/Data/.config/QQ/NapCat", isDirectory: true)
        }
        .padding()
        .frame(width: 560)
    }
}

private struct PathRow: View {
    let title: String
    let path: String
    let isDirectory: Bool

    @State private var missing = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                guard FileManager.default.fileExists(atPath: path) else {
                    missing = true
                    return
                }
                let url = URL(fileURLWithPath: path)
                if isDirectory {
                    NSWorkspace.shared.open(url)
                } else {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            } label: {
                Label("打开 \(title)", systemImage: "folder")
                    .font(.caption)
            }
            Text(path)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .alert("提示", isPresented: $missing) {
            Button("好") { missing = false }
        } message: {
            Text("未找到该路径：\n\(path)")
        }
    }
}

#Preview {
    ContentView()
}
