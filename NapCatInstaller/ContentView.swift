import SwiftUI

struct ContentView: View {
    @AppStorage("GitHubProxyIndex") private var proxyIndex: Int = -1
    @State private var qqVersion = QQVersion.loading
    @State private var patchStatus = PatchStatus.loading
    @State private var napcatVersion = NapcatVersion.loading
    @State private var buttonClicked = false
    
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
                NapcatInstallationButton(version: napcatVersion, status: patchStatus, proxy: proxy) {
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
            if showPatch {
                NapcatPatchView(status: patchStatus, refreshHandler: updatePatchStatus)
            }
            if showUsage {
                NapcatUsageView()
            }
            if let url = try? getWebUILink() {
                Button("打开WebUI…") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .padding()
        .animation(.default, value: qqVersion)
        .animation(.default, value: patchStatus)
        .animation(.default, value: napcatVersion)
        .task(id: buttonClicked) {
            updateAll()
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
            guard let local = try getLocalNapcat(),
                let remote = try await getRemoteNapcat()
            else {
                napcatVersion = .missing
                return
            }
            if local.compare(remote, options: .numeric) == .orderedAscending {
                napcatVersion = .outdated(local, remote)
            } else {
                napcatVersion = .latest(remote)
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
    let refreshHandler: () -> Void
    @State private var loading = false
    @State private var showLogs = false
    @State private var failed = false
    @State private var error: Error?
    @StateObject private var installationProgress = InstallationProgress()
    var body: some View {
        switch version {
        case .loading, .failed:
            Button {
                fatalError("Should not be reachable")
            } label: {
                Label("安装", systemImage: "shippingbox.circle")
            }
            .disabled(true)
        case .missing, .outdated:
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    Task {
                        loading = true
                        showLogs = true
                        installationProgress.reset()
                        installationProgress.isInstalling = true
                        do {
                            try await installNapcat(proxy: proxy, progress: installationProgress)
                        } catch {
                            failed = true
                            self.error = error
                        }
                        installationProgress.isInstalling = false
                        loading = false
                        refreshHandler()
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
                .alert("发生错误", isPresented: $failed, presenting: error) { _ in
                    Button("好") { failed = false }
                } message: { e in
                    Text(e.localizedDescription)
                }
                if showLogs {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            ProgressView(value: installationProgress.progress) {
                                Text("进度: \(installationProgress.progress.formatted(.percent))")
                            }
                            .progressViewStyle(.linear)
                            Button("清除") {
                                showLogs = false
                                installationProgress.reset()
                            }
                            .disabled(installationProgress.isInstalling)
                        }
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(installationProgress.logs) { log in
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
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
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
        case .latest:
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
            .alert("发生错误", isPresented: $failed, presenting: error) { _ in
                Button("好") { failed = false }
            } message: { e in
                Text(e.localizedDescription)
            }
            .disabled(status.patched)
            .help("请先还原再卸载")
        }
    }
}

private struct InstallationProgressView: View {
    let progress: InstallationProgress
    var body: some View {
        VStack(spacing: 20) {
            Text("安装进度")
                .font(.headline)
            ProgressView(value: progress.progress) {
                Text("进度: \(progress.progress.formatted(.percent))")
            }
            .progressViewStyle(.linear)
            .frame(width: 400)
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
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(.callout, design: .monospaced))
            .padding(.horizontal)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.selection)
            .cornerRadius(5)
            HStack {
                Spacer()
                Button("关闭") {
                    if !progress.isInstalling {
                        progress.reset()
                    }
                }
                .disabled(progress.isInstalling)
            }
        }
        .padding()
        .frame(width: 500)
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
            patchButton(title: "切换程序入口「 原版 QQ 」", action: getQQPackageBak)
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

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            HStack(spacing: 20) {
                Button("🚀 启动 NapCat") {
                    launchNapcat()
                }
                Button("🐧 启动 原版QQ") {
                    launchOriginalQQ()
                }
            }
            if let error = launchError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            Text("提示：启动原版QQ建议切换程序入口，否则可能会出现问题！")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func getQQAppURL() -> URL? {
        let defaultPath = "/Applications/QQ.app"
        let url = URL(fileURLWithPath: defaultPath)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    private func launchNapcat() {
        guard let qqAppURL = getQQAppURL() else {
            launchError = "未找到 QQ.app，请确认已安装 QQ"
            return
        }
        let executableURL = qqAppURL.appendingPathComponent("Contents/MacOS/QQ")
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            launchError = "QQ 可执行文件不存在或不可执行"
            return
        }
        let path = executableURL.path
        let escapedPath = path.replacingOccurrences(of: "'", with: "'\\''")
        let script = """
        tell application "Terminal"
            activate
            if (count of windows) is 0 then
                do script "'\(escapedPath)' --no-sandbox"
            else
                tell front window
                    do script "'\(escapedPath)' --no-sandbox" in selected tab
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

    private func launchOriginalQQ() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "QQ.app", "-n"]
        do {
            try process.run()
            launchError = nil
        } catch {
            launchError = "启动失败: \(error.localizedDescription)"
        }
    }
}

#Preview {
    ContentView()
}
