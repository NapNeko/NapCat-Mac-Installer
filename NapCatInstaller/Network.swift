import Foundation
import CryptoKit

struct ReleaseInfo {
    let version: String
    let digest: String
    let assetURL: URL
}

struct GitHubProxy: Identifiable, Hashable {
    let name: String
    let baseURL: String?
    var id: String { baseURL ?? "direct" }

    func url(for resource: String) throws -> URL {
        guard let resourceURL = URL(string: resource), resourceURL.scheme == "https", resourceURL.host != nil else {
            throw URLError(.badURL)
        }
        guard let baseURL else { return resourceURL }
        guard let prefix = URLComponents(string: baseURL),
              let scheme = prefix.scheme, ["http", "https"].contains(scheme), prefix.host?.isEmpty == false,
              prefix.query == nil, prefix.fragment == nil else {
            throw URLError(.badURL)
        }
        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard let result = URL(string: "\(base)/\(resource)") else { throw URLError(.badURL) }
        return result
    }

    static let allProxies = [
        GitHubProxy(name: "GitHub 原生 / 系统代理", baseURL: nil),
        GitHubProxy(name: "ghfast.top", baseURL: "https://ghfast.top"),
        GitHubProxy(name: "ghproxy.net", baseURL: "https://ghproxy.net"),
        GitHubProxy(name: "gh-proxy.com", baseURL: "https://gh-proxy.com"),
    ]
}

struct ResolvedRelease {
    let proxy: GitHubProxy
    let release: ReleaseInfo
}

private let releaseSession: URLSession = {
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = 8
    configuration.timeoutIntervalForResource = 12
    return URLSession(configuration: configuration)
}()

func fetchReleaseInfo(proxy: GitHubProxy, session: URLSession = releaseSession) async throws -> ReleaseInfo {
    let api = "https://api.github.com/repos/NapNeko/NapCatQQ/releases/latest"
    var request = URLRequest(url: try proxy.url(for: api))
    request.timeoutInterval = 8
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    let (data, response) = try await session.data(for: request)
    guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
        throw URLError(.badServerResponse)
    }
    guard let release = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let tag = release["tag_name"] as? String, !tag.isEmpty,
          let assets = release["assets"] as? [[String: Any]],
          let asset = assets.first(where: { $0["name"] as? String == "NapCat.Shell.zip" }),
          let address = asset["browser_download_url"] as? String,
          address.hasPrefix("https://github.com/NapNeko/NapCatQQ/releases/download/\(tag)/"),
          let assetURL = URL(string: address),
          let digest = asset["digest"] as? String,
          digest.range(of: "^sha256:[a-fA-F0-9]{64}$", options: .regularExpression) != nil else {
        throw URLError(.cannotParseResponse)
    }
    return ReleaseInfo(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag,
                       digest: String(digest.dropFirst(7)).lowercased(), assetURL: assetURL)
}

func resolveRelease(proxy: GitHubProxy? = nil, candidates: [GitHubProxy] = GitHubProxy.allProxies,
                    session: URLSession = releaseSession) async throws -> ResolvedRelease {
    if let proxy {
        return ResolvedRelease(proxy: proxy, release: try await fetchReleaseInfo(proxy: proxy, session: session))
    }
    return try await withThrowingTaskGroup(of: ResolvedRelease.self) { group in
        for candidate in candidates {
            group.addTask {
                ResolvedRelease(proxy: candidate, release: try await fetchReleaseInfo(proxy: candidate, session: session))
            }
        }
        while let result = await group.nextResult() {
            if case .success(let release) = result {
                group.cancelAll()
                return release
            }
        }
        throw NSError(domain: "NapCatNetwork", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "所有下载线路均不可用，请检查系统代理、证书信任或自定义加速地址。"])
    }
}

func sha256Digest(of url: URL) throws -> String {
    SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
}

func verifyArtifact(at url: URL, expectedDigest: String) throws {
    guard try sha256Digest(of: url) == expectedDigest else {
        throw NSError(domain: "NapCatNetwork", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "下载文件的 SHA-256 与发布记录不一致。"])
    }
}

class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let destinationURL: URL
    var completionHandler: ((Result<URL, Error>) -> Void)?
    var progressHandler: ((Double, Int64, Int64) -> Void)?

    init(destinationURL: URL) {
        self.destinationURL = destinationURL
    }

    private func complete(_ result: Result<URL, Error>) {
        let callback = completionHandler
        completionHandler = nil
        callback?(result)
    }

    func finishDownload(at location: URL, response: URLResponse?) {
        do {
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            try FileManager.default.copyItem(at: location, to: destinationURL)
            complete(.success(destinationURL))
        } catch {
            complete(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        finishDownload(at: location, response: downloadTask.response)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            progressHandler?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), totalBytesWritten, totalBytesExpectedToWrite)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { complete(.failure(error)) }
    }
}

func downloadArtifact(from url: URL, to destination: URL,
                      progress: ((Double, Int64, Int64) -> Void)? = nil) async throws -> URL {
    let delegate = DownloadDelegate(destinationURL: destination)
    delegate.progressHandler = progress
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = 30
    configuration.timeoutIntervalForResource = 1800
    let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    defer { session.invalidateAndCancel() }
    return try await withCheckedThrowingContinuation { continuation in
        delegate.completionHandler = { continuation.resume(with: $0) }
        session.downloadTask(with: url).resume()
    }
}
