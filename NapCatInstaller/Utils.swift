import AppKit
import Combine
import ZIPFoundation
import CryptoKit

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let message: String
}

class InstallationProgress: ObservableObject {
    @Published var logs: [LogEntry] = []
    @Published var progress: Double = 0.0
    @Published var isInstalling = false
    
    func addLog(_ message: String) {
        DispatchQueue.main.async {
            self.logs.append(LogEntry(message: message))
        }
    }
    
    func updateProgress(_ value: Double) {
        DispatchQueue.main.async {
            self.progress = value
        }
    }
    
    func reset() {
        DispatchQueue.main.async {
            self.logs = []
            self.progress = 0.0
            self.isInstalling = false
        }
    }
}

let appURL = URL(fileURLWithPath: "/Applications/QQ.app/Contents/Resources/app")
let homeDir = NSHomeDirectory()
let containerURL = URL(fileURLWithPath: "\(homeDir)/Library/Containers/com.tencent.qq/Data")
let docURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
let datURL = containerURL.appendingPathComponent("Library/Application Support/QQ/NapCat", isDirectory: true)
let versionsURL = containerURL.appendingPathComponent("Library/Application Support/QQ/versions", isDirectory: true)
private func getJSONObject(url: URL) throws -> [NSString: Any]? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let data = try Data(contentsOf: url)
    let obj = try JSONSerialization.jsonObject(with: data)
    return obj as? [NSString: Any]
}

enum QQVersion: Equatable {
    case loading
    case missing
    case installed(String)
    case failed(String)
}

let packageURL = appURL.appendingPathComponent("package.json")

func getQQVersion() throws -> String? {
    guard let package = try getJSONObject(url: packageURL) else { return nil }
    return package["version"] as? String
}

enum NapcatVersion: Equatable {
    case loading
    case missing
    case installed(String)
    case outdated(String, String)
    case latest(String)
    case failed(String)

    var installed: Bool {
        switch self {
        case .installed, .outdated, .latest:
            return true
        default:
            return false
        }
    }
}

private let napcatURL = docURL.appendingPathComponent("napcat")
private let napcatPackageURL = napcatURL.appendingPathComponent("package.json")

func getLocalNapcat() throws -> String? {
    guard let dict = try getJSONObject(url: napcatPackageURL) else { return nil }
    return dict["version"] as? String
}

func getRemoteNapcat(proxy: GitHubProxy? = nil) async throws -> String {
    try await resolveRelease(proxy: proxy).release.version
}

func removeNapcat() throws {
    try? FileManager.default.removeItem(at: loaderURL)
    try? FileManager.default.removeItem(at: napcatURL)
}

func installNapcat(proxy: GitHubProxy? = nil, progress: InstallationProgress? = nil) async throws {
    let fileManager = FileManager.default
    progress?.updateProgress(0.0)
    progress?.addLog("开始安装 NapCat...")
    let stagingURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let extractedURL = stagingURL.appendingPathComponent("NapCat", isDirectory: true)
    try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: stagingURL) }
    progress?.updateProgress(0.05)
    progress?.addLog("创建目录: \(napcatURL.path)")
    try fileManager.createDirectory(at: napcatURL, withIntermediateDirectories: true)
    progress?.addLog("目录创建完成")
    progress?.addLog("正在连接 GitHub API...")
    let resolved = try await resolveRelease(proxy: proxy)
    let releaseInfo = resolved.release
    progress?.addLog("使用下载线路: \(resolved.proxy.name)，NapCat v\(releaseInfo.version)")
    let url = try resolved.proxy.url(for: releaseInfo.assetURL.absoluteString)
    progress?.updateProgress(0.2)
    let downloadProgress = progress ?? InstallationProgress()
    var lastReportedProgress = 0.0
    let downloadLocation = try await downloadArtifact(from: url, to: stagingURL.appendingPathComponent("download.zip")) { fraction, written, total in
        downloadProgress.updateProgress(0.2 + fraction * 0.6)
        if fraction - lastReportedProgress >= 0.1 || fraction >= 1 {
            lastReportedProgress = fraction
            downloadProgress.addLog(String(format: "下载进度: %.1f MB / %.1f MB (%.1f%%)",
                                           Double(written) / 1048576, Double(total) / 1048576, fraction * 100))
        }
    }
    downloadProgress.updateProgress(0.82)
    try verifyArtifact(at: downloadLocation, expectedDigest: releaseInfo.digest)
    downloadProgress.addLog("SHA-256 校验通过")
    downloadProgress.updateProgress(0.85)
    downloadProgress.addLog("解压到临时目录...")
    do {
        try fileManager.unzipItem(at: downloadLocation, to: extractedURL)
    } catch {
        downloadProgress.addLog("解压失败: \(error.localizedDescription)")
        try? fileManager.removeItem(at: downloadLocation)
        throw error
    }
    downloadProgress.updateProgress(0.95)
    downloadProgress.addLog("解压完成")
    guard fileManager.fileExists(atPath: extractedURL.appendingPathComponent("napcat.mjs").path) else {
        downloadProgress.addLog("错误: 解压目录中缺少 napcat.mjs，文件可能已损坏或被篡改")
        try? fileManager.removeItem(at: downloadLocation)
        throw NSError(domain: "InstallError", code: 3, userInfo: [NSLocalizedDescriptionKey: "napcat.mjs not found after extraction"])
    }
    let packageJsonURL = extractedURL.appendingPathComponent("package.json")
    do {
        guard fileManager.fileExists(atPath: packageJsonURL.path) else {
            downloadProgress.addLog("错误: package.json 不存在于解压目录中")
            throw NSError(domain: "InstallError", code: 1, userInfo: [NSLocalizedDescriptionKey: "package.json not found"])
        }
        let jsonData = try Data(contentsOf: packageJsonURL)
        var jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any]
        guard jsonObject != nil else {
            downloadProgress.addLog("错误: package.json 格式无效")
            throw NSError(domain: "InstallError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON"])
        }
        jsonObject?["version"] = releaseInfo.version
        let newJsonData = try JSONSerialization.data(withJSONObject: jsonObject!, options: .prettyPrinted)
        try newJsonData.write(to: packageJsonURL)
    } catch {
        downloadProgress.addLog("修改 version 失败: \(error.localizedDescription)")
        throw error
    }
    for item in try fileManager.contentsOfDirectory(at: extractedURL, includingPropertiesForKeys: nil) {
        let destination = napcatURL.appendingPathComponent(item.lastPathComponent)
        if ["config", "plugins"].contains(item.lastPathComponent), fileManager.fileExists(atPath: destination.path) {
            for defaultItem in try fileManager.contentsOfDirectory(at: item, includingPropertiesForKeys: nil) {
                let defaultDestination = destination.appendingPathComponent(defaultItem.lastPathComponent)
                if !fileManager.fileExists(atPath: defaultDestination.path) {
                    try fileManager.copyItem(at: defaultItem, to: defaultDestination)
                }
            }
        } else {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: item, to: destination)
        }
    }
    downloadProgress.updateProgress(1.0)
    downloadProgress.addLog("安装完成")
}

enum PatchStatus: Equatable {
    case loading
    case original
    case napcat
    case custom(String)
    case failed(String)
    var patched: Bool {
        return self == .napcat
    }
    static let originalLoaders = [
        "./application.asar/app_launcher/index.js",
        "./application/app_launcher/index.js",
        "./app_launcher/index.js",
    ]
}

let napcatLoader = "../../../../..\(docURL.path)/loadNapCat.js"

func getAppLoader() throws -> String? {
    guard FileManager.default.fileExists(atPath: packageURL.path) else { return nil }
    let data = try Data(contentsOf: packageURL)
    let obj = try JSONSerialization.jsonObject(with: data)
    guard let dict = obj as? [NSString: Any] else { return nil }
    return dict["main"] as? String
}

private let loaderURL = docURL.appendingPathComponent("loadNapCat.js")

private func createLoader() throws {
    let loaderContent = #"""
    const path = require('node:path');
    const { pathToFileURL } = require('node:url');
    const loadNapcat = process.argv.includes('--no-sandbox');
    const package = require('/Applications/QQ.app/Contents/Resources/app/package.json');
    if (loadNapcat) {
        (async () => {
            await import(pathToFileURL(path.join(__dirname, 'napcat/napcat.mjs')).href);
        })();
    } else {
        require('\#(appURL.path)/app_launcher/index.js');
        setImmediate(() => {
            if (global.launcher && global.launcher.installPathPkgJson) {
                global.launcher.installPathPkgJson.main = ((version) => {
                    if (version >= 29271) return "./application.asar/app_launcher/index.js";
                    if (version >= 28060) return "./application/app_launcher/index.js";
                    return "./app_launcher/index.js";
                })(package.buildVersion);
            }
        });
    }
    """#
    try loaderContent.write(to: loaderURL, atomically: true, encoding: .utf8)
}

private func relativePath(from sourceDir: URL, to targetFile: URL) -> String {
    let src = sourceDir.pathComponents
    let dst = targetFile.pathComponents
    var i = 0
    while i < src.count && i < dst.count && src[i] == dst[i] {
        i += 1
    }
    var parts = Array(repeating: "..", count: src.count - i)
    parts.append(contentsOf: dst[i...])
    return parts.joined(separator: "/")
}

private func originalLoader(for buildVersion: String?) -> String {
    guard let buildVersion, let version = Int(buildVersion) else {
        return "./application.asar/app_launcher/index.js"
    }
    if version >= 29271 { return "./application.asar/app_launcher/index.js" }
    if version >= 28060 { return "./application/app_launcher/index.js" }
    return "./app_launcher/index.js"
}

private func hotUpdatePackageURLs() -> [URL] {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: versionsURL.path),
        let versionDirs = try? fileManager.contentsOfDirectory(atPath: versionsURL.path)
    else { return [] }
    return versionDirs.compactMap { dir in
        let url = versionsURL.appendingPathComponent(dir)
            .appendingPathComponent("QQUpdate.app/Contents/Resources/app/package.json")
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }
}

@discardableResult
func patchHotUpdatePackages() throws -> Int {
    var patched = 0
    for pkgURL in hotUpdatePackageURLs() {
        guard var dict = try getJSONObject(url: pkgURL), let main = dict["main"] as? String else { continue }
        let appDir = pkgURL.deletingLastPathComponent()
        let loaderPath = relativePath(from: appDir, to: loaderURL)
        guard main != loaderPath else { continue }
        dict["main"] = loaderPath
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .withoutEscapingSlashes])
        try data.write(to: pkgURL)
        patched += 1
    }
    return patched
}

@discardableResult
func restoreHotUpdatePackages() throws -> Int {
    var restored = 0
    for pkgURL in hotUpdatePackageURLs() {
        guard var dict = try getJSONObject(url: pkgURL),
            let main = dict["main"] as? String,
            main.contains("loadNapCat.js")
        else { continue }
        let original = originalLoader(for: dict["buildVersion"] as? String)
        guard main != original else { continue }
        dict["main"] = original
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .withoutEscapingSlashes])
        try data.write(to: pkgURL)
        restored += 1
    }
    return restored
}

private func permissionFixHint(for raw: String) -> String {
    var message = raw
    if message.localizedCaseInsensitiveContains("not permitted") {
        message += "\n\n解决办法：请在「系统设置 → 隐私与安全性 → App 管理」中添加本程序（NapCat安装器），然后重新点击按钮重试。"
        message += "\n如已添加仍失败，请先移除后重新添加，并完全退出本程序后重试。"
    }
    return message
}

@discardableResult
func getQQPackageBak() -> Bool {
    let backupURL = URL(fileURLWithPath: packageURL.path + ".bak")
    guard FileManager.default.fileExists(atPath: backupURL.path) else {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "错误"
            alert.informativeText = "未找到备份文件：\n\(backupURL.path)"
            alert.alertStyle = .critical
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }
        return false
    }
    let alert = NSAlert()
    alert.messageText = "需要管理员权限"
    alert.informativeText = "请输入您的电脑开机密码（用于恢复 QQ 配置文件）："
    alert.alertStyle = .informational
    alert.addButton(withTitle: "确定")
    alert.addButton(withTitle: "取消")
    let textField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
    textField.placeholderString = "密码"
    alert.accessoryView = textField
    let response = alert.runModal()
    guard response == .alertFirstButtonReturn else {
        return false
    }
    let password = textField.stringValue
    guard !password.isEmpty else {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "提示"
            alert.informativeText = "未输入密码，操作已取消。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }
        return false
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
    process.arguments = ["-S", "cp", backupURL.path, packageURL.path]
    let inputPipe = Pipe()
    inputPipe.fileHandleForWriting.write((password + "\n").data(using: .utf8)!)
    inputPipe.fileHandleForWriting.closeFile()
    process.standardInput = inputPipe
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe
    do {
        try process.run()
        process.waitUntilExit()
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
        DispatchQueue.main.async {
            if process.terminationStatus == 0 {
                var info = "package.json 已恢复为备份文件"
                do {
                    let restored = try restoreHotUpdatePackages()
                    if restored > 0 {
                        info += "，并已恢复 \(restored) 个 QQ 热更新包入口"
                    }
                } catch {
                    info += "\n警告：QQ 热更新包入口恢复失败（\(error.localizedDescription)）"
                }
                let alert = NSAlert()
                alert.messageText = "成功"
                alert.informativeText = info
                alert.alertStyle = .informational
                alert.addButton(withTitle: "确定")
                alert.runModal()
            } else {
                let msg = errorOutput.isEmpty ? output : errorOutput
                let alert = NSAlert()
                alert.messageText = "恢复失败"
                alert.informativeText = "命令执行失败：\n\(permissionFixHint(for: msg))"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "确定")
                alert.runModal()
            }
        }
        return process.terminationStatus == 0
    } catch {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "执行错误"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }
        return false
    }
}

func setQQPackageBak() throws {
    guard FileManager.default.fileExists(atPath: packageURL.path) else {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "错误"
            alert.informativeText = "未找到原始文件：\n\(packageURL.path)"
            alert.alertStyle = .critical
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }
        return
    }
    let alert = NSAlert()
    alert.messageText = "需要管理员权限"
    alert.informativeText = "请输入您的电脑开机密码（用于备份并修改 QQ 配置文件）："
    alert.alertStyle = .informational
    alert.addButton(withTitle: "确定")
    alert.addButton(withTitle: "取消")
    let textField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
    textField.placeholderString = "密码"
    alert.accessoryView = textField
    let response = alert.runModal()
    guard response == .alertFirstButtonReturn else {
        return
    }
    let password = textField.stringValue
    guard !password.isEmpty else {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "提示"
            alert.informativeText = "未输入密码，操作已取消。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }
        return
    }
    let backupURL = URL(fileURLWithPath: packageURL.path + ".bak")
    let backupProcess = Process()
    backupProcess.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
    backupProcess.arguments = ["-S", "cp", packageURL.path, backupURL.path]
    let backupInputPipe = Pipe()
    backupInputPipe.fileHandleForWriting.write((password + "\n").data(using: .utf8)!)
    backupInputPipe.fileHandleForWriting.closeFile()
    backupProcess.standardInput = backupInputPipe
    backupProcess.standardOutput = Pipe()
    backupProcess.standardError = Pipe()
    do {
        try backupProcess.run()
        backupProcess.waitUntilExit()
    } catch {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "备份错误"
            alert.informativeText = "无法执行备份命令：\(error.localizedDescription)"
            alert.alertStyle = .critical
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }
        return
    }
    guard backupProcess.terminationStatus == 0 else {
        let errorData = (backupProcess.standardError as? Pipe)?.fileHandleForReading.readDataToEndOfFile() ?? Data()
        let errorMsg = String(data: errorData, encoding: .utf8) ?? "未知错误"
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "备份失败"
            alert.informativeText = "备份原文件失败：\n\(permissionFixHint(for: errorMsg))"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }
        return
    }
    try createLoader()
    guard var qq = try getJSONObject(url: packageURL) else { return }
    qq["main"] = napcatLoader
    let data = try JSONSerialization.data(withJSONObject: qq, options: [.prettyPrinted, .withoutEscapingSlashes])
    let tempDir = FileManager.default.temporaryDirectory
    let tempFile = tempDir.appendingPathComponent("napcat_package.json")
    try data.write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }
    let writeProcess = Process()
    writeProcess.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
    writeProcess.arguments = ["-S", "cp", tempFile.path, packageURL.path]
    let writeInputPipe = Pipe()
    writeInputPipe.fileHandleForWriting.write((password + "\n").data(using: .utf8)!)
    writeInputPipe.fileHandleForWriting.closeFile()
    writeProcess.standardInput = writeInputPipe
    writeProcess.standardOutput = Pipe()
    writeProcess.standardError = Pipe()
    do {
        try writeProcess.run()
        writeProcess.waitUntilExit()
    } catch {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "写入错误"
            alert.informativeText = "无法执行写入命令：\(error.localizedDescription)"
            alert.alertStyle = .critical
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }
        return
    }
    let outputData = (writeProcess.standardOutput as? Pipe)?.fileHandleForReading.readDataToEndOfFile() ?? Data()
    let errorData = (writeProcess.standardError as? Pipe)?.fileHandleForReading.readDataToEndOfFile() ?? Data()
    let output = String(data: outputData, encoding: .utf8) ?? ""
    let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
    DispatchQueue.main.async {
        if writeProcess.terminationStatus == 0 {
            var info = "已备份原文件并直接写入修改后的 package.json"
            do {
                let patched = try patchHotUpdatePackages()
                if patched > 0 {
                    info += "，并已同步修改 \(patched) 个 QQ 热更新包入口"
                }
            } catch {
                info += "\n警告：QQ 热更新包入口同步失败（\(error.localizedDescription)）"
            }
            let alert = NSAlert()
            alert.messageText = "成功"
            alert.informativeText = info
            alert.alertStyle = .informational
            alert.addButton(withTitle: "确定")
            alert.runModal()
        } else {
            let msg = errorOutput.isEmpty ? output : errorOutput
            let alert = NSAlert()
            alert.messageText = "写入失败"
            alert.informativeText = "写入新内容失败：\n\(permissionFixHint(for: msg))"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }
    }
}

private let webuiURL = datURL.appendingPathComponent("config/webui.json", isDirectory: false)

func getWebUILink() throws -> URL? {
    guard let dict = try getJSONObject(url: webuiURL),
          let port = dict["port"] as? Int,
          let token = dict["token"] as? String
    else {
        return nil
    }
    return URL(string: "http://127.0.0.1:\(port)/webui?token=\(token)")
}
