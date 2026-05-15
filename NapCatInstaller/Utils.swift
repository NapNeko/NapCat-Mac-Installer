import AppKit
import Foundation
import SwiftUI
import ZIPFoundation

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
        logs = []
        progress = 0.0
        isInstalling = false
    }
}

class DownloadDelegate: NSObject, URLSessionDownloadDelegate, URLSessionDelegate {
    let progress: InstallationProgress
    var completionHandler: ((URL?, Error?) -> Void)?
    private var lastReportedProgress: Double = 0.0
    
    init(progress: InstallationProgress) {
        self.progress = progress
        super.init()
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let fileManager = FileManager.default
        let destinationURL = napcatURL.appendingPathComponent("download.zip")
        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: location, to: destinationURL)
            progress.addLog("下载文件已保存至: \(destinationURL.lastPathComponent)")
            completionHandler?(destinationURL, nil)
        } catch {
            progress.addLog("保存下载文件失败: \(error.localizedDescription)")
            completionHandler?(nil, error)
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let downloadProgress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        let overallProgress = 0.2 + (downloadProgress * 0.6)
        progress.updateProgress(overallProgress)
        if downloadProgress - lastReportedProgress >= 0.1 || downloadProgress >= 1.0 {
            lastReportedProgress = downloadProgress
            let mbWritten = Double(totalBytesWritten) / (1024 * 1024)
            let mbTotal = Double(totalBytesExpectedToWrite) / (1024 * 1024)
            progress.addLog(String(format: "下载进度: %.1f MB / %.1f MB (%.1f%%)",
                                   mbWritten, mbTotal, downloadProgress * 100))
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            progress.addLog("下载任务失败: \(error.localizedDescription)")
            completionHandler?(nil, error)
        }
    }
    
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            if let serverTrust = challenge.protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

class SpeedTestDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            if let serverTrust = challenge.protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

let appURL = URL(fileURLWithPath: "/Applications/QQ.app/Contents/Resources/app")
let containerURL = URL(fileURLWithPath: "/Users/\(NSUserName())/Library/Containers/com.tencent.qq/Data")
let docURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
let datURL = containerURL.appendingPathComponent("Library/Application Support/QQ/NapCat", isDirectory: true)
private let downloadCacheURL = containerURL.appendingPathComponent(".download", isDirectory: true)

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
    case outdated(String, String)
    case latest(String)
    case failed(String)

    var installed: Bool {
        switch self {
        case .outdated, .latest:
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

func getRemoteNapcat() async throws -> String? {
    let url = URL(string: "https://raw.githubusercontent.com/NapNeko/NapCatQQ/refs/heads/main/package.json")!
    let (data, response) = try await URLSession.shared.data(from: url)
    guard let httpResponse = response as? HTTPURLResponse,
          httpResponse.statusCode == 200 else {
        return nil
    }
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    return json?["version"] as? String
}

func removeNapcat() throws {
    try? FileManager.default.removeItem(at: loaderURL)
    try? FileManager.default.removeItem(at: napcatURL)
}

struct GitHubProxy: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let baseURL: String
    let urlFormat: URLFormat
    
    enum URLFormat {
        case direct
        case github
        case raw
        case custom
    }
    
    init(name: String, baseURL: String, format: URLFormat = .github) {
        self.name = name
        self.baseURL = baseURL
        self.urlFormat = format
    }
    
    func url(for resource: String) -> URL {
        let cleanResource = resource
            .replacingOccurrences(of: "https://github.com/", with: "")
            .replacingOccurrences(of: "https://raw.githubusercontent.com/", with: "")
        switch urlFormat {
        case .direct:
            return URL(string: resource)!
        case .github:
            return URL(string: "\(baseURL)/\(cleanResource)")!
        case .raw:
            return URL(string: "\(baseURL)/\(cleanResource)")!
        case .custom:
            if baseURL.hasPrefix("ssh://") || baseURL.isEmpty {
                return URL(string: resource)!
            }
            return URL(string: "\(baseURL)/\(cleanResource)")!
        }
    }
    
    static let allProxies: [GitHubProxy] = {
        let githubProxies = [
            ("@X.I.U/XIU2", "https://gh.h233.eu.org"),
            ("热心网友", "https://rapidgit.jjda.de5.net"),
            ("@mtr-static-official", "https://gh.ddlc.top"),
            ("gh-proxy.com", "https://gh-proxy.org"),
            ("gh-proxy.com (cdn)", "https://cdn.gh-proxy.org"),
            ("gh-proxy.com (edgeone)", "https://edgeone.gh-proxy.org"),
            ("@yionchilau", "https://ghproxy.it"),
            ("blog.boki.moe", "https://github.boki.moe"),
            ("gh-proxy.net", "https://gh-proxy.net"),
            ("gh.jasonzeng.dev", "https://gh.jasonzeng.dev"),
            ("gh.monlor.com", "https://gh.monlor.com"),
            ("fastgit.cc", "https://fastgit.cc"),
            ("github.tbedu.top", "https://github.tbedu.top"),
            ("firewall.lxstd.org", "https://firewall.lxstd.org"),
            ("github.ednovas.xyz", "https://github.ednovas.xyz"),
            ("ghfile.geekertao.top", "https://ghfile.geekertao.top"),
            ("ghp.keleyaa.com", "https://ghp.keleyaa.com"),
            ("gh.chjina.com", "https://gh.chjina.com"),
            ("ghpxy.hwinzniej.top", "https://ghpxy.hwinzniej.top"),
            ("cdn.crashmc.com", "https://cdn.crashmc.com"),
            ("git.yylx.win", "https://git.yylx.win"),
            ("gitproxy.mrhjx.cn", "https://gitproxy.mrhjx.cn"),
            ("ghproxy.cxkpro.top", "https://ghproxy.cxkpro.top"),
            ("gh.xxooo.cf", "https://gh.xxooo.cf"),
            ("github.limoruirui.com", "https://github.limoruirui.com"),
            ("gh.idayer.com", "https://gh.idayer.com"),
            ("gh.llkk.cc", "https://gh.llkk.cc"),
            ("gh.nxnow.top", "https://gh.nxnow.top"),
            ("gh.zwy.one", "https://gh.zwy.one"),
            ("ghproxy.monkeyray.net", "https://ghproxy.monkeyray.net"),
            ("gh.xx9527.cn", "https://gh.xx9527.cn"),
            ("ghproxy.link", "https://ghfast.top"),
            ("ucdn.me", "https://wget.la"),
            ("gh-proxy.com (hk)", "https://hk.gh-proxy.org"),
        ]
        let customProxies = [
            ("GitHub 原生", "", URLFormat.direct),
            ("@Lufs's", "https://cors.isteed.cc", URLFormat.custom),
            ("raw.ihtw.moe", "https://raw.ihtw.moe", URLFormat.custom),
            ("github.com/xixu-me/Xget", "https://xget.xi-xu.me/gh", URLFormat.custom),
            ("GitClone", "https://gitclone.com", URLFormat.custom),
            ("Github Fast", "https://githubfast.com", URLFormat.custom),
            ("JSDelivr CDN", "https://fastly.jsdelivr.net/gh", URLFormat.raw),
        ]
        var proxies: [GitHubProxy] = []
        proxies.append(contentsOf: githubProxies.map { GitHubProxy(name: $0.0, baseURL: "\($0.1)/https://github.com", format: .github) })
        proxies.append(contentsOf: customProxies.map { GitHubProxy(name: $0.0, baseURL: $0.1, format: $0.2) })
        proxies.insert(GitHubProxy(name: "GitHub 原生", baseURL: "", format: .direct), at: 0)
        return proxies
    }()
    
    static func auto(progress: InstallationProgress? = nil) async throws -> GitHubProxy {
        let check = "https://github.com/NapNeko/NapCatQQ/releases/latest/download/NapCat.Shell.zip"
        let delegate = SpeedTestDelegate()
        progress?.addLog("开始测速所有代理...")
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 3.0
        config.timeoutIntervalForResource = 5.0
        let totalProxies = allProxies.filter { !$0.baseURL.isEmpty }.count
        var testedCount = 0
        return await withThrowingTaskGroup(of: (GitHubProxy, TimeInterval).self) { group in
            for proxy in allProxies where !proxy.baseURL.isEmpty {
                group.addTask {
                    let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
                    let start = Date()
                    var request = URLRequest(url: proxy.url(for: check))
                    request.setValue("bytes=0-1", forHTTPHeaderField: "Range")
                    let (data, response) = try await session.data(for: request)
                    guard let httpResponse = response as? HTTPURLResponse,
                        (200..<300).contains(httpResponse.statusCode),
                        data.count >= 2,
                        data[0] == 0x50, data[1] == 0x4B
                    else {
                        throw URLError(.badServerResponse)
                    }
                    
                    let duration = Date().timeIntervalSince(start)
                    return (proxy, duration)
                }
            }
            var fastestProxy: GitHubProxy?
            var fastestTime: TimeInterval = .infinity
            var successCount = 0
            var failureCount = 0
            while let result = await group.nextResult() {
                testedCount += 1
                switch result {
                case .success(let (proxy, time)):
                    successCount += 1
                    if time < fastestTime {
                        fastestTime = time
                        fastestProxy = proxy
                        progress?.addLog(String(format: "发现更快代理: %@ (%.2f秒) [%d/%d]", proxy.name, time, testedCount, totalProxies))
                    }
                case .failure(_):
                    failureCount += 1
                    if testedCount % 5 == 0 {
                        progress?.addLog("测速进度: \(testedCount)/\(totalProxies) (成功: \(successCount), 失败: \(failureCount))")
                    }
                }
            }
            progress?.addLog("测速完成: \(successCount) 个代理可用, \(failureCount) 个代理失败")
            if let fastest = fastestProxy {
                progress?.addLog(String(format: "最快代理: %@ (%.2f秒)", fastest.name, fastestTime))
                return fastest
            }
            progress?.addLog("所有代理均不可用，使用 GitHub 原生")
            return GitHubProxy(name: "GitHub 原生", baseURL: "", format: .direct)
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(baseURL)
    }

    static func == (lhs: GitHubProxy, rhs: GitHubProxy) -> Bool {
        return lhs.name == rhs.name && lhs.baseURL == rhs.baseURL
    }
}

func installNapcat(proxy: GitHubProxy? = nil, progress: InstallationProgress? = nil) async throws {
    let fileManager = FileManager.default
    progress?.updateProgress(0.0)
    progress?.addLog("开始安装 NapCat...")
    if fileManager.fileExists(atPath: napcatURL.path) {
        progress?.addLog("移除已存在的 NapCat: \(napcatURL.path)")
        do {
            try fileManager.removeItem(at: napcatURL)
            progress?.addLog("移除完成")
        } catch {
            progress?.addLog("移除失败: \(error.localizedDescription)")
            throw error
        }
    }
    progress?.updateProgress(0.05)
    progress?.addLog("创建目录: \(napcatURL.path)")
    try fileManager.createDirectory(at: napcatURL, withIntermediateDirectories: true)
    progress?.addLog("目录创建完成")
    let asset = "https://github.com/NapNeko/NapCatQQ/releases/latest/download/NapCat.Shell.zip"
    let url: URL
    if let proxy {
        progress?.addLog("使用代理: \(proxy.name)")
        url = proxy.url(for: asset)
    } else {
        progress?.updateProgress(0.1)
        let fastestProxy = try await GitHubProxy.auto(progress: progress)
        url = fastestProxy.url(for: asset)
    }
    progress?.updateProgress(0.2)
    progress?.addLog("开始下载: \(url.absoluteString)")
    let downloadProgress = progress ?? InstallationProgress()
    let delegate = DownloadDelegate(progress: downloadProgress)
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 30.0
    config.timeoutIntervalForResource = 300.0
    let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    let downloadTask = session.downloadTask(with: url)
    let downloadLocation = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
        delegate.completionHandler = { location, error in
            if let error = error {
                downloadProgress.addLog("下载失败: \(error.localizedDescription)")
                continuation.resume(throwing: error)
            } else if let location = location {
                continuation.resume(returning: location)
            } else {
                downloadProgress.addLog("下载失败: 未知错误")
                continuation.resume(throwing: URLError(.unknown))
            }
        }
        downloadTask.resume()
    }
    guard fileManager.fileExists(atPath: downloadLocation.path) else {
        downloadProgress.addLog("下载失败: 临时文件不存在")
        throw URLError(.fileDoesNotExist)
    }
    downloadProgress.updateProgress(0.8)
    downloadProgress.addLog("下载完成")
    downloadProgress.updateProgress(0.85)
    downloadProgress.addLog("解压到: \(napcatURL.path)")
    do {
        try fileManager.unzipItem(at: downloadLocation, to: napcatURL)
    } catch {
        downloadProgress.addLog("解压失败: \(error.localizedDescription)")
        try? fileManager.removeItem(at: downloadLocation)
        throw error
    }
    downloadProgress.updateProgress(0.95)
    downloadProgress.addLog("解压完成")
    try? fileManager.removeItem(at: downloadLocation)
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
    const hasNapcatParam = process.argv.includes('--no-sandbox');
    const package = require('/Applications/QQ.app/Contents/Resources/app/package.json');
    if (hasNapcatParam) {
        (async () => {
            await import('file://\#(docURL.path)/napcat/napcat.mjs');
        })();
    } else {
        require('\#(appURL.path)/app_launcher/index.js');
        setImmediate(() => {
            global.launcher.installPathPkgJson.main = ((version) => {
                if (version >= 29271) return "./application.asar/app_launcher/index.js";
                if (version >= 28060) return "./application/app_launcher/index.js";
                return "./app_launcher/index.js";
            })(package.buildVersion);
        });
    }
    """#
    try loaderContent.write(to: loaderURL, atomically: true, encoding: .utf8)
}

func getQQPackage() {
    NSWorkspace.shared.activateFileViewerSelecting([packageURL])
}

func getPatchedPackage() throws {
    try createLoader()
    guard var qq = try getJSONObject(url: packageURL) else { return }
    qq["main"] = napcatLoader
    let data = try JSONSerialization.data(withJSONObject: qq, options: [.prettyPrinted, .withoutEscapingSlashes])
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("package.json")
    try data.write(to: url, options: .atomic)
    NSWorkspace.shared.activateFileViewerSelecting([url])
}

let napcatInstructions = #"""
    # \#(NSLocalizedString("命令行启动，注入 NapCat", comment: ""))
    $ /Applications/QQ.app/Contents/MacOS/QQ --no-sandbox
    # \#(NSLocalizedString("参数可以加 -q <QQ号> 快速登录", comment: ""))

    # \#(NSLocalizedString("正常启动 QQ GUI，不注入 NapCat", comment: ""))
    $ open -a QQ.app -n
    """#

private let webuiURL = datURL.appendingPathComponent("config/webui.json", isDirectory: false)

func getWebUILink() throws -> URL? {
    guard let dict = try getJSONObject(url: webuiURL),
          let port = dict["port"] as? Int,
          let prefix = dict["prefix"] as? String,
          let token = dict["token"] as? String
    else {
        return nil
    }
    return URL(string: "http://127.0.0.1:\(port)\(prefix)/webui?token=\(token)")
}
