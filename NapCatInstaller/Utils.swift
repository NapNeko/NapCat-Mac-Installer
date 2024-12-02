//
//  Utils.swift
//  NapCatInstaller
//
//  Created by hguandl on 2024/10/2.
//

import AppKit
import Foundation
import ZIPFoundation

let appURL = URL(fileURLWithPath: "/Applications/QQ.app/Contents/Resources/app")
let containerURL = URL(fileURLWithPath: "/Users/\(NSUserName())/Library/Containers/com.tencent.qq/Data")
let docURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
let datURL = containerURL.appendingPathComponent("Library/Application Support/QQ/NapCat", isDirectory: true)

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
    let (data, _) = try await URLSession.shared.data(from: URL(string: "https://nclatest.znin.net/")!)
    let obj = try JSONSerialization.jsonObject(with: data)
    guard let dict = obj as? [NSString: Any] else { return nil }
    guard let tagName = dict["tag_name"] as? String else { return nil }
    return tagName.replacingOccurrences(of: "v", with: "")
}

func removeNapcat() throws {
    try? FileManager.default.removeItem(at: loaderURL)
    try FileManager.default.removeItem(at: napcatURL)
}

enum GitHubProxy: String, CaseIterable {
    case direct
    case moeyy
    case ghproxy
    case ghProxy
    case haod

    var name: String {
        switch self {
        case .direct:
            NSLocalizedString("不使用", comment: "")
        case .moeyy:
            NSLocalizedString("moeyy", comment: "")
        case .ghproxy:
            NSLocalizedString("ghproxy", comment: "")
        case .ghProxy:
            NSLocalizedString("gh-proxy", comment: "")
        case .haod:
            NSLocalizedString("haod", comment: "")
        }
    }

    func url(for resource: String) -> URL {
        switch self {
        case .direct:
            URL(string: resource)!
        case .moeyy:
            URL(string: "https://github.moeyy.xyz/\(resource)")!
        case .ghproxy:
            URL(string: "https://mirror.ghproxy.com/\(resource)")!
        case .ghProxy:
            URL(string: "https://gh-proxy.com/\(resource)")!
        case .haod:
            URL(string: "https://x.haod.me/\(resource)")!
        }
    }

    static func auto() async throws -> GitHubProxy {
        try await withThrowingTaskGroup(of: GitHubProxy.self) { group in
            let check = "https://raw.githubusercontent.com/NapNeko/NapCatQQ/main/package.json"
            for proxy in GitHubProxy.allCases {
                group.addTask {
                    let _ = try await URLSession.shared.data(from: proxy.url(for: check))
                    return proxy
                }
            }
            var failure: Error?
            while let result = await group.nextResult() {
                switch result {
                case .success(let proxy):
                    group.cancelAll()
                    return proxy
                case .failure(let error):
                    failure = error
                }
            }
            throw failure!
        }
    }
}

func installNapcat(proxy: GitHubProxy? = nil) async throws {
    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: napcatURL.path) {
        try fileManager.removeItem(at: napcatURL)
    }
    try fileManager.createDirectory(at: napcatURL, withIntermediateDirectories: true)
    let asset = "https://github.com/NapNeko/NapCatQQ/releases/latest/download/NapCat.Shell.zip"
    let url: URL
    if let proxy {
        url = proxy.url(for: asset)
    } else {
        url = try await GitHubProxy.auto().url(for: asset)
    }
    let (zip, _) = try await URLSession.shared.download(from: url)
    try fileManager.unzipItem(at: zip, to: napcatURL)
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
    try #"""
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
    .write(to: loaderURL, atomically: true, encoding: .utf8)
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
