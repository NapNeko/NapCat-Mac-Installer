import func SwiftUI.__designTimeFloat
import func SwiftUI.__designTimeString
import func SwiftUI.__designTimeInteger
import func SwiftUI.__designTimeBoolean

#sourceLocation(file: "/Users/sylker/Downloads/NapCat-Mac-Installer/NapCatInstaller/ContentView.swift", line: 1)
import SwiftUI

struct ContentView: View {
    @AppStorage("GitHubProxyIndex") private var proxyIndex: Int = -1
    @State private var qqVersion = QQVersion.loading
    @State private var patchStatus = PatchStatus.loading
    @State private var napcatVersion = NapcatVersion.loading
    @State private var buttonClicked = false
    
    private var proxy: GitHubProxy? {
        if proxyIndex < __designTimeInteger("#3023_0", fallback: 0) || proxyIndex >= GitHubProxy.allProxies.count {
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
        VStack(spacing: __designTimeInteger("#3023_1", fallback: 20)) {
            HStack {
                VStack(alignment: .trailing, spacing: __designTimeInteger("#3023_2", fallback: 5)) {
                    Text(__designTimeString("#3023_3", fallback: "QQ版本"))
                    Text(__designTimeString("#3023_4", fallback: "NapCat版本"))
                    Text(__designTimeString("#3023_5", fallback: "程序入口"))
                }
                VStack(alignment: .leading, spacing: __designTimeInteger("#3023_6", fallback: 5)) {
                    QQVersionView(version: qqVersion)
                    NapcatVersionView(version: napcatVersion)
                    PatchStatusView(status: patchStatus)
                }
                .foregroundColor(.secondary)
            }
            Divider()
            HStack(spacing: __designTimeInteger("#3023_7", fallback: 15)) {
                Button {
                    buttonClicked.toggle()
                } label: {
                    Label(__designTimeString("#3023_8", fallback: "刷新"), systemImage: __designTimeString("#3023_9", fallback: "arrow.clockwise.circle"))
                }
                NapcatInstallationButton(version: napcatVersion, status: patchStatus, proxy: proxy) {
                    buttonClicked.toggle()
                }
                Picker(__designTimeString("#3023_10", fallback: "代理"), selection: $proxyIndex) {
                    Text(__designTimeString("#3023_11", fallback: "自动检测")).tag(__designTimeInteger("#3023_12", fallback: -1))
                    ForEach(Array(GitHubProxy.allProxies.enumerated()), id: \.offset) { index, proxyItem in
                        Text(proxyItem.name)
                            .tag(index)
                    }
                }
                .frame(maxWidth: __designTimeInteger("#3023_13", fallback: 150))
            }
            if showPatch {
                NapcatPatchView(status: patchStatus)
            }
            if showUsage {
                NapcatUsageView()
            }
            if let url = try? getWebUILink() {
                Button(__designTimeString("#3023_14", fallback: "打开WebUI…")) {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .padding()
        .animation(.default, value: qqVersion)
        .animation(.default, value: patchStatus)
        .animation(.default, value: napcatVersion)
        .task(id: buttonClicked) {
            updateQQVersion()
            updatePatchStatus()
            await updateNapcatVersion()
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

    private func updatePatchStatus() {
        do {
            guard let loader = try getAppLoader() else {
                patchStatus = .custom(__designTimeString("#3023_15", fallback: ""))
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
            Text(Image(systemName: __designTimeString("#3023_16", fallback: "ellipsis.circle"))) + Text(__designTimeString("#3023_17", fallback: " 正在读取…"))
        case .missing:
            Text(Image(systemName: __designTimeString("#3023_18", fallback: "questionmark.circle"))).foregroundColor(.yellow) + Text(__designTimeString("#3023_19", fallback: " 未安装"))
        case .installed(let v):
            Text(Image(systemName: __designTimeString("#3023_20", fallback: "checkmark.circle"))).foregroundColor(.green) + Text(" \(v)")
        case .failed(let d):
            (Text(Image(systemName: __designTimeString("#3023_21", fallback: "xmark.circle"))).foregroundColor(.red) + Text(__designTimeString("#3023_22", fallback: " 发生错误"))).help(d)
        }
    }
}

private struct NapcatVersionView: View {
    let version: NapcatVersion
    var body: some View {
        switch version {
        case .loading:
            Text(Image(systemName: __designTimeString("#3023_23", fallback: "ellipsis.circle"))) + Text(__designTimeString("#3023_24", fallback: " 正在加载…"))
        case .missing:
            Text(Image(systemName: __designTimeString("#3023_25", fallback: "questionmark.circle"))).foregroundColor(.yellow) + Text(__designTimeString("#3023_26", fallback: " 未安装"))
        case .outdated(let l, let r):
            Text(Image(systemName: __designTimeString("#3023_27", fallback: "arrow.up.circle"))).foregroundColor(.blue) + Text(" \(l)，可升级\(r)")
        case .latest(let v):
            Text(Image(systemName: __designTimeString("#3023_28", fallback: "checkmark.circle"))).foregroundColor(.green) + Text(" \(v)，已是最新")
        case .failed(let d):
            (Text(Image(systemName: __designTimeString("#3023_29", fallback: "xmark.circle"))).foregroundColor(.red) + Text(__designTimeString("#3023_30", fallback: " 发生错误"))).help(d)
        }
    }
}

private struct PatchStatusView: View {
    let status: PatchStatus
    var body: some View {
        switch status {
        case .loading:
            Text(Image(systemName: __designTimeString("#3023_31", fallback: "ellipsis.circle"))) + Text(__designTimeString("#3023_32", fallback: " 正在读取…"))
        case .original:
            Text(Image(systemName: __designTimeString("#3023_33", fallback: "ellipsis.circle"))).foregroundColor(.blue) + Text(__designTimeString("#3023_34", fallback: " 原版QQ"))
        case .napcat:
            Text(Image(systemName: __designTimeString("#3023_35", fallback: "checkmark.circle"))).foregroundColor(.green) + Text(__designTimeString("#3023_36", fallback: " NapCat"))
        case .custom(let loader):
            Text(Image(systemName: __designTimeString("#3023_37", fallback: "questionmark.circle"))).foregroundColor(.yellow) + Text(" 自定义 \(loader)")
        case .failed(let d):
            (Text(Image(systemName: __designTimeString("#3023_38", fallback: "xmark.circle"))).foregroundColor(.red) + Text(__designTimeString("#3023_39", fallback: " 发生错误"))).help(d)
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
                fatalError(__designTimeString("#3023_40", fallback: "Should not be reachable"))
            } label: {
                Label(__designTimeString("#3023_41", fallback: "安装"), systemImage: __designTimeString("#3023_42", fallback: "shippingbox.circle"))
            }
            .disabled(__designTimeBoolean("#3023_43", fallback: true))
        case .missing, .outdated:
            VStack(alignment: .leading, spacing: __designTimeInteger("#3023_44", fallback: 8)) {
                Button {
                    Task {
                        loading = __designTimeBoolean("#3023_45", fallback: true)
                        showLogs = __designTimeBoolean("#3023_46", fallback: true)
                        installationProgress.reset()
                        installationProgress.isInstalling = __designTimeBoolean("#3023_47", fallback: true)
                        do {
                            try await installNapcat(proxy: proxy, progress: installationProgress)
                        } catch {
                            failed = __designTimeBoolean("#3023_48", fallback: true)
                            self.error = error
                        }
                        installationProgress.isInstalling = __designTimeBoolean("#3023_49", fallback: false)
                        loading = __designTimeBoolean("#3023_50", fallback: false)
                        refreshHandler()
                    }
                } label: {
                    switch version {
                    case .missing:
                        Label(__designTimeString("#3023_51", fallback: "安装"), systemImage: __designTimeString("#3023_52", fallback: "shippingbox.circle"))
                    case .outdated:
                        Label(__designTimeString("#3023_53", fallback: "更新"), systemImage: __designTimeString("#3023_54", fallback: "arrow.up.circle"))
                    default:
                        fatalError(__designTimeString("#3023_55", fallback: "Should not be reachable"))
                    }
                }
                .alert(__designTimeString("#3023_56", fallback: "发生错误"), isPresented: $failed, presenting: error) { _ in
                    Button(__designTimeString("#3023_57", fallback: "好")) { failed = __designTimeBoolean("#3023_58", fallback: false) }
                } message: { e in
                    Text(e.localizedDescription)
                }
                if showLogs {
                    VStack(alignment: .leading, spacing: __designTimeInteger("#3023_59", fallback: 4)) {
                        HStack {
                            ProgressView(value: installationProgress.progress) {
                                Text("进度: \(Int(installationProgress.progress * __designTimeInteger("#3023_60", fallback: 100)))%")
                            }
                            .progressViewStyle(.linear)
                            Button(__designTimeString("#3023_61", fallback: "清除")) {
                                showLogs = __designTimeBoolean("#3023_62", fallback: false)
                                installationProgress.reset()
                            }
                            .disabled(installationProgress.isInstalling)
                        }
                        ScrollView {
                            VStack(alignment: .leading, spacing: __designTimeInteger("#3023_63", fallback: 4)) {
                                ForEach(installationProgress.logs) { log in
                                    HStack(alignment: .top, spacing: __designTimeInteger("#3023_64", fallback: 8)) {
                                        Text(log.timestamp, style: .time)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .frame(width: __designTimeInteger("#3023_65", fallback: 60), alignment: .leading)
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
                        .padding(.vertical, __designTimeInteger("#3023_66", fallback: 5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.selection)
                        .cornerRadius(__designTimeInteger("#3023_67", fallback: 5))
                    }
                }
            }
        case .latest:
            Button {
                do {
                    try removeNapcat()
                } catch {
                    failed = __designTimeBoolean("#3023_68", fallback: true)
                    self.error = error
                }
                refreshHandler()
            } label: {
                Label(__designTimeString("#3023_69", fallback: "卸载"), systemImage: __designTimeString("#3023_70", fallback: "trash.circle"))
            }
            .alert(__designTimeString("#3023_71", fallback: "发生错误"), isPresented: $failed, presenting: error) { _ in
                Button(__designTimeString("#3023_72", fallback: "好")) { failed = __designTimeBoolean("#3023_73", fallback: false) }
            } message: { e in
                Text(e.localizedDescription)
            }
            .disabled(status.patched)
            .help(__designTimeString("#3023_74", fallback: "请先还原再卸载"))
        }
    }
}

private struct InstallationProgressView: View {
    let progress: InstallationProgress
    var body: some View {
        VStack(spacing: __designTimeInteger("#3023_75", fallback: 20)) {
            Text(__designTimeString("#3023_76", fallback: "安装进度"))
                .font(.headline)
            ProgressView(value: progress.progress) {
                Text("进度: \(Int(progress.progress * __designTimeInteger("#3023_77", fallback: 100)))%")
            }
            .progressViewStyle(.linear)
            .frame(width: __designTimeInteger("#3023_78", fallback: 400))
            ScrollView {
                VStack(alignment: .leading, spacing: __designTimeInteger("#3023_79", fallback: 4)) {
                    ForEach(progress.logs) { log in
                        HStack(alignment: .top, spacing: __designTimeInteger("#3023_80", fallback: 8)) {
                            Text(log.timestamp, style: .time)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: __designTimeInteger("#3023_81", fallback: 60), alignment: .leading)
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
            .padding(.vertical, __designTimeInteger("#3023_82", fallback: 5))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.selection)
            .cornerRadius(__designTimeInteger("#3023_83", fallback: 5))
            HStack {
                Spacer()
                Button(__designTimeString("#3023_84", fallback: "关闭")) {
                    if !progress.isInstalling {
                        progress.reset()
                    }
                }
                .disabled(progress.isInstalling)
            }
        }
        .padding()
        .frame(width: __designTimeInteger("#3023_85", fallback: 500))
    }
}

private struct NapcatPatchView: View {
    let status: PatchStatus
    @State private var failed = false
    @State private var error: Error?
    var body: some View {
        switch status {
        case .loading, .failed:
            EmptyView()
        case .original, .custom:
            VStack(alignment: .leading) {
                HStack {
                    Text(__designTimeString("#3023_86", fallback: "请备份"))
                    Button(__designTimeString("#3023_87", fallback: "QQ应用目录"), action: getQQPackage)
                    Text(__designTimeString("#3023_88", fallback: "下的package.json文件"))
                    Button(__designTimeString("#3023_89", fallback: "立即备份"), action: backupPackageJSON)
                }
                HStack {
                    Text(__designTimeString("#3023_90", fallback: "然后使用此"))
                    Button(__designTimeString("#3023_91", fallback: "修改的文件")) {
                        do {
                            try getPatchedPackage()
                        } catch {
                            failed = __designTimeBoolean("#3023_92", fallback: true)
                            self.error = error
                        }
                    }
                    Text(__designTimeString("#3023_93", fallback: "覆盖，最后点击刷新"))
                }
            }
            .alert(__designTimeString("#3023_94", fallback: "发生错误"), isPresented: $failed, presenting: error) { _ in
                Button(__designTimeString("#3023_95", fallback: "好")) { failed = __designTimeBoolean("#3023_96", fallback: false) }
            } message: { e in
                Text(e.localizedDescription)
            }
        case .napcat:
            VStack(alignment: .leading) {
                Text(__designTimeString("#3023_97", fallback: "如果要还原，请将备份的package.json文件放回"))
                HStack {
                    Button(__designTimeString("#3023_98", fallback: "QQ应用目录"), action: getQQPackage)
                    Text(__designTimeString("#3023_99", fallback: "，然后点击刷新"))
                }
            }
        }
    }
}

private struct NapcatUsageView: View {
    var body: some View {
        Text(napcatInstructions)
            .textSelection(.enabled)
            .font(.system(.callout, design: .monospaced))
            .padding(.horizontal)
            .padding(.vertical, __designTimeInteger("#3023_100", fallback: 5))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.selection)
            .cornerRadius(__designTimeInteger("#3023_101", fallback: 5))
    }
}

#Preview {
    ContentView()
}
