import func SwiftUI.__designTimeFloat
import func SwiftUI.__designTimeString
import func SwiftUI.__designTimeInteger
import func SwiftUI.__designTimeBoolean

#sourceLocation(file: "/Users/sylker/Downloads/NapCat-Mac-Installer/NapCatInstaller/ContentView.swift", line: 1)
//
//  ContentView.swift
//  NapCatInstaller
//
//  Created by hguandl on 2024/10/1.
//  Modified by SweelLong on 2026/5/15.
//

import SwiftUI

struct ContentView: View {
    @AppStorage("GitHubProxy") private var proxy: GitHubProxy?
    @State private var qqVersion = QQVersion.loading
    @State private var patchStatus = PatchStatus.loading
    @State private var napcatVersion = NapcatVersion.loading
    @State private var buttonClicked = false

    private var showPatch: Bool {
        return napcatVersion.installed || patchStatus.patched
    }

    private var showUsage: Bool {
        return patchStatus.patched
    }

    var body: some View {
        VStack(spacing: __designTimeInteger("#8042_0", fallback: 20)) {
            HStack {
                VStack(alignment: .trailing, spacing: __designTimeInteger("#8042_1", fallback: 5)) {
                    Text(__designTimeString("#8042_2", fallback: "QQ版本"))
                    Text(__designTimeString("#8042_3", fallback: "NapCat版本"))
                    Text(__designTimeString("#8042_4", fallback: "程序入口"))
                }
                VStack(alignment: .leading, spacing: __designTimeInteger("#8042_5", fallback: 5)) {
                    QQVersionView(version: qqVersion)
                    NapcatVersionView(version: napcatVersion)
                    PatchStatusView(status: patchStatus)
                }
                .foregroundColor(.secondary)
            }
            Divider()
            HStack(spacing: __designTimeInteger("#8042_6", fallback: 15)) {
                Button {
                    buttonClicked.toggle()
                } label: {
                    Label(__designTimeString("#8042_7", fallback: "刷新"), systemImage: __designTimeString("#8042_8", fallback: "arrow.clockwise.circle"))
                }
                NapcatInstallationButton(version: napcatVersion, status: patchStatus, proxy: proxy) {
                    buttonClicked.toggle()
                }
                Picker(__designTimeString("#8042_9", fallback: "代理"), selection: $proxy) {
                    Text(__designTimeString("#8042_10", fallback: "自动检测")).tag(GitHubProxy?.none)
                    ForEach(GitHubProxy.allCases, id: \.self) { proxyCase in
                        Text(proxyCase.name)
                            .tag(proxyCase as GitHubProxy?)
                    }
                }
                .frame(maxWidth: __designTimeInteger("#8042_11", fallback: 150))
            }
            if showPatch {
                NapcatPatchView(status: patchStatus)
            }
            if showUsage {
                NapcatUsageView()
            }
            if let url = try? getWebUILink() {
                Button(__designTimeString("#8042_12", fallback: "打开WebUI…")) {
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
                patchStatus = .custom(__designTimeString("#8042_13", fallback: ""))
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
            Text(Image(systemName: __designTimeString("#8042_14", fallback: "ellipsis.circle"))) + Text(__designTimeString("#8042_15", fallback: " 正在读取…"))
        case .missing:
            Text(Image(systemName: __designTimeString("#8042_16", fallback: "questionmark.circle"))).foregroundColor(.yellow) + Text(__designTimeString("#8042_17", fallback: " 未安装"))
        case .installed(let v):
            Text(Image(systemName: __designTimeString("#8042_18", fallback: "checkmark.circle"))).foregroundColor(.green) + Text(" \(v)")
        case .failed(let d):
            (Text(Image(systemName: __designTimeString("#8042_19", fallback: "xmark.circle"))).foregroundColor(.red) + Text(__designTimeString("#8042_20", fallback: " 发生错误"))).help(d)
        }
    }
}

private struct NapcatVersionView: View {
    let version: NapcatVersion

    var body: some View {
        switch version {
        case .loading:
            Text(Image(systemName: __designTimeString("#8042_21", fallback: "ellipsis.circle"))) + Text(__designTimeString("#8042_22", fallback: " 正在加载…"))
        case .missing:
            Text(Image(systemName: __designTimeString("#8042_23", fallback: "questionmark.circle"))).foregroundColor(.yellow) + Text(__designTimeString("#8042_24", fallback: " 未安装"))
        case .outdated(let l, let r):
            Text(Image(systemName: __designTimeString("#8042_25", fallback: "arrow.up.circle"))).foregroundColor(.blue) + Text(" \(l)，可升级\(r)")
        case .latest(let v):
            Text(Image(systemName: __designTimeString("#8042_26", fallback: "checkmark.circle"))).foregroundColor(.green) + Text(" \(v)，已是最新")
        case .failed(let d):
            (Text(Image(systemName: __designTimeString("#8042_27", fallback: "xmark.circle"))).foregroundColor(.red) + Text(__designTimeString("#8042_28", fallback: " 发生错误"))).help(d)
        }
    }
}

private struct PatchStatusView: View {
    let status: PatchStatus

    var body: some View {
        switch status {
        case .loading:
            Text(Image(systemName: __designTimeString("#8042_29", fallback: "ellipsis.circle"))) + Text(__designTimeString("#8042_30", fallback: " 正在读取…"))
        case .original:
            Text(Image(systemName: __designTimeString("#8042_31", fallback: "ellipsis.circle"))).foregroundColor(.blue) + Text(__designTimeString("#8042_32", fallback: " 原版QQ"))
        case .napcat:
            Text(Image(systemName: __designTimeString("#8042_33", fallback: "checkmark.circle"))).foregroundColor(.green) + Text(__designTimeString("#8042_34", fallback: " NapCat"))
        case .custom(let loader):
            Text(Image(systemName: __designTimeString("#8042_35", fallback: "questionmark.circle"))).foregroundColor(.yellow) + Text(" 自定义 \(loader)")
        case .failed(let d):
            (Text(Image(systemName: __designTimeString("#8042_36", fallback: "xmark.circle"))).foregroundColor(.red) + Text(__designTimeString("#8042_37", fallback: " 发生错误"))).help(d)
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
                fatalError(__designTimeString("#8042_38", fallback: "Should not be reachable"))
            } label: {
                Label(__designTimeString("#8042_39", fallback: "安装"), systemImage: __designTimeString("#8042_40", fallback: "shippingbox.circle"))
            }
            .disabled(__designTimeBoolean("#8042_41", fallback: true))
        case .missing, .outdated:
            Button {
                Task {
                    loading = __designTimeBoolean("#8042_42", fallback: true)
                    do {
                        try await installNapcat(proxy: proxy)
                    } catch {
                        failed = __designTimeBoolean("#8042_43", fallback: true)
                        self.error = error
                    }
                    loading = __designTimeBoolean("#8042_44", fallback: false)
                    refreshHandler()
                }
            } label: {
                switch version {
                case .missing:
                    Label(__designTimeString("#8042_45", fallback: "安装"), systemImage: __designTimeString("#8042_46", fallback: "shippingbox.circle"))
                case .outdated:
                    Label(__designTimeString("#8042_47", fallback: "更新"), systemImage: __designTimeString("#8042_48", fallback: "arrow.up.circle"))
                default:
                    fatalError(__designTimeString("#8042_49", fallback: "Should not be reachable"))
                }
            }
            .sheet(isPresented: $loading) {
                ProgressView()
            }
            .alert(__designTimeString("#8042_50", fallback: "发生错误"), isPresented: $failed, presenting: error) { _ in
                Button(__designTimeString("#8042_51", fallback: "好")) { failed = __designTimeBoolean("#8042_52", fallback: false) }
            } message: { e in
                Text(e.localizedDescription)
            }
        case .latest:
            Button {
                do {
                    try removeNapcat()
                } catch {
                    failed = __designTimeBoolean("#8042_53", fallback: true)
                    self.error = error
                }
                refreshHandler()
            } label: {
                Label(__designTimeString("#8042_54", fallback: "卸载"), systemImage: __designTimeString("#8042_55", fallback: "trash.circle"))
            }
            .alert(__designTimeString("#8042_56", fallback: "发生错误"), isPresented: $failed, presenting: error) { _ in
                Button(__designTimeString("#8042_57", fallback: "好")) { failed = __designTimeBoolean("#8042_58", fallback: false) }
            } message: { e in
                Text(e.localizedDescription)
            }
            .disabled(status.patched)
            .help(__designTimeString("#8042_59", fallback: "请先还原再卸载"))
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
                    Text(__designTimeString("#8042_60", fallback: "请备份"))
                    Button(__designTimeString("#8042_61", fallback: "QQ应用目录"), action: getQQPackage)
                    Text(__designTimeString("#8042_62", fallback: "下的package.json文件"))
                }
                HStack {
                    Text(__designTimeString("#8042_63", fallback: "然后使用此"))
                    Button(__designTimeString("#8042_64", fallback: "修改的文件")) {
                        do {
                            try getPatchedPackage()
                        } catch {
                            failed = __designTimeBoolean("#8042_65", fallback: true)
                            self.error = error
                        }
                    }
                    Text(__designTimeString("#8042_66", fallback: "覆盖，最后点击刷新"))
                }
            }
            .alert(__designTimeString("#8042_67", fallback: "发生错误"), isPresented: $failed, presenting: error) { _ in
                Button(__designTimeString("#8042_68", fallback: "好")) { failed = __designTimeBoolean("#8042_69", fallback: false) }
            } message: { e in
                Text(e.localizedDescription)
            }
        case .napcat:
            VStack(alignment: .leading) {
                Text(__designTimeString("#8042_70", fallback: "如果要还原，请将备份的package.json文件放回"))
                HStack {
                    Button(__designTimeString("#8042_71", fallback: "QQ应用目录"), action: getQQPackage)
                    Text(__designTimeString("#8042_72", fallback: "，然后点击刷新"))
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
            .padding(.vertical, __designTimeInteger("#8042_73", fallback: 5))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.selection)
            .cornerRadius(__designTimeInteger("#8042_74", fallback: 5))
    }
}

#Preview {
    ContentView()
}
