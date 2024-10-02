//
//  ContentView.swift
//  NapCatInstaller
//
//  Created by hguandl on 2024/10/1.
//

import SwiftUI

struct ContentView: View {
    @State private var qqVersion = QQVersion.loading
    @State private var patchStatus = PatchStatus.loading
    @State private var napcatVersion = NapcatVersion.loading

    @State private var buttonClicked = false
    @State private var proxy: GitHubProxy?

    private var showPatch: Bool {
        return napcatVersion.installed || patchStatus.patched
    }

    private var showUsage: Bool {
        return patchStatus.patched
    }

    var body: some View {
        VStack(spacing: 20) {
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
                Picker("代理", selection: $proxy) {
                    Text("自动检测").tag(GitHubProxy?.none)
                    Text("不使用").tag(GitHubProxy.direct)
                    Text("moeyy").tag(GitHubProxy.moeyy)
                    Text("ghproxy").tag(GitHubProxy.ghproxy)
                    Text("gh-proxy").tag(GitHubProxy.ghProxy)
                    Text("haod").tag(GitHubProxy.haod)
                }
                .frame(maxWidth: 150)
            }
            if showPatch {
                NapcatPatchView(status: patchStatus)
            }
            if showUsage {
                NapcatUsageView()
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
                patchStatus = .custom("")
                return
            }
            switch loader {
            case originalLoader:
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
    @State private var failed = false
    @State private var error: Error?

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
            Button {
                Task {
                    loading = true
                    do {
                        try await installNapcat(proxy: proxy)
                    } catch {
                        failed = true
                        self.error = error
                    }
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
            .sheet(isPresented: $loading) {
                ProgressView()
            }
            .alert("发生错误", isPresented: $failed, presenting: error) { _ in
                Button("好") { failed = false }
            } message: { e in
                Text(e.localizedDescription)
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
                    Text("请备份")
                    Button("QQ应用目录", action: getQQPackage)
                    Text("下的package.json文件")
                }
                HStack {
                    Text("然后使用此")
                    Button("修改的文件") {
                        do {
                            try getPatchedPackage()
                        } catch {
                            failed = true
                            self.error = error
                        }
                    }
                    Text("覆盖，最后点击刷新")
                }
            }
            .alert("发生错误", isPresented: $failed, presenting: error) { _ in
                Button("好") { failed = false }
            } message: { e in
                Text(e.localizedDescription)
            }
        case .napcat:
            VStack(alignment: .leading) {
                Text("如果要还原，请将备份的package.json文件放回")
                HStack {
                    Button("QQ应用目录", action: getQQPackage)
                    Text("，然后点击刷新")
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
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.selection)
            .cornerRadius(5)
    }
}

#Preview {
    ContentView()
}
