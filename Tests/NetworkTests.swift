import XCTest
@testable import InstallerNetwork

final class FixtureProtocol: URLProtocol {
    static var responder: ((URLRequest) throws -> (Int, Data))!
    static var addresses: [String] = []
    static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.addresses.append(request.url!.absoluteString)
        Self.lock.unlock()
        do {
            let (status, data) = try Self.responder(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class NetworkTests: XCTestCase {
    var session: URLSession!
    let direct = GitHubProxy(name: "direct", baseURL: nil)
    let mirror = GitHubProxy(name: "mirror", baseURL: "https://mirror.example/prefix")
    let digest = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

    override func setUp() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureProtocol.self]
        configuration.timeoutIntervalForRequest = 1
        configuration.timeoutIntervalForResource = 2
        session = URLSession(configuration: configuration)
        FixtureProtocol.addresses = []
    }

    override func tearDown() { session.invalidateAndCancel() }

    func releaseJSON(includeDigest: Bool = true) throws -> Data {
        var asset: [String: Any] = [
            "name": "NapCat.Shell.zip",
            "browser_download_url": "https://github.com/NapNeko/NapCatQQ/releases/download/v4.18.35/NapCat.Shell.zip",
        ]
        if includeDigest { asset["digest"] = "sha256:" + digest }
        return try JSONSerialization.data(withJSONObject: ["tag_name": "v4.18.35", "assets": [asset]])
    }

    func testProxyKeepsFullResourceAddress() throws {
        for resource in ["https://api.github.com/repos/NapNeko/NapCatQQ/releases/latest",
                         "https://github.com/NapNeko/NapCatQQ/releases/download/v4.18.35/NapCat.Shell.zip",
                         "https://raw.githubusercontent.com/NapNeko/NapCatQQ/main/package.json"] {
            XCTAssertEqual(try mirror.url(for: resource).absoluteString, mirror.baseURL! + "/" + resource)
            XCTAssertEqual(try direct.url(for: resource).absoluteString, resource)
        }
        for prefix in ["", "ssh://example.com", "https://", "https://mirror.example/?token=1"] {
            XCTAssertThrowsError(try GitHubProxy(name: "invalid", baseURL: prefix).url(for: "https://github.com/file"))
        }
    }

    func testExplicitMirrorControlsMetadataAndPinnedAsset() async throws {
        let json = try releaseJSON()
        FixtureProtocol.responder = { _ in (200, json) }
        let resolved = try await resolveRelease(proxy: mirror, session: session)
        XCTAssertEqual(resolved.release.version, "4.18.35")
        XCTAssertEqual(resolved.release.digest, digest)
        XCTAssertEqual(FixtureProtocol.addresses, [mirror.baseURL! + "/https://api.github.com/repos/NapNeko/NapCatQQ/releases/latest"])
        XCTAssertTrue(try resolved.proxy.url(for: resolved.release.assetURL.absoluteString).absoluteString
            .contains("/releases/download/v4.18.35/"))
    }

    func testExplicitFailureDoesNotSelectAnotherRoute() async {
        FixtureProtocol.responder = { _ in throw URLError(.timedOut) }
        do {
            _ = try await resolveRelease(proxy: mirror, session: session)
            XCTFail("an explicit failed route must fail")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
        }
        XCTAssertEqual(FixtureProtocol.addresses.count, 1)
    }

    func testAutoCanSelectDirectAndRejectsHTML() async throws {
        let json = try releaseJSON()
        FixtureProtocol.responder = { request in
            request.url!.host == "api.github.com" ? (200, json) : (200, Data("<html>portal</html>".utf8))
        }
        let resolved = try await resolveRelease(candidates: [mirror, direct], session: session)
        XCTAssertEqual(resolved.proxy, direct)
    }

    func testAllFailedRoutesReportFailure() async {
        FixtureProtocol.responder = { _ in (503, Data()) }
        do {
            _ = try await resolveRelease(candidates: [mirror, direct], session: session)
            XCTFail("no route has supplied a release")
        } catch {
            XCTAssertEqual((error as NSError).domain, "NapCatNetwork")
        }
    }

    func testMetadataRequiresDigestAndRealAsset() async throws {
        let missingDigest = try releaseJSON(includeDigest: false)
        for body in [missingDigest, Data("{\"tag_name\":\"v4.18.35\",\"assets\":[]}".utf8)] {
            FixtureProtocol.responder = { _ in (200, body) }
            do {
                _ = try await fetchReleaseInfo(proxy: direct, session: session)
                XCTFail("incomplete metadata must fail")
            } catch {
                XCTAssertEqual((error as? URLError)?.code, .cannotParseResponse)
            }
        }
    }

    func testDownloadRejectsHTTPErrorWithoutReplacingExistingFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("partial")
        let destination = folder.appendingPathComponent("download.zip")
        try Data("error page".utf8).write(to: source)
        try Data("previous file".utf8).write(to: destination)
        let delegate = DownloadDelegate(destinationURL: destination)
        var callbacks = 0
        delegate.completionHandler = { result in
            callbacks += 1
            if case .success = result { XCTFail("HTTP error must fail") }
        }
        let response = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 404,
                                       httpVersion: nil, headerFields: nil)
        delegate.finishDownload(at: source, response: response)
        delegate.urlSession(session, task: session.dataTask(with: URL(string: "https://example.com")!),
                            didCompleteWithError: URLError(.networkConnectionLost))
        XCTAssertEqual(callbacks, 1)
        XCTAssertEqual(try String(contentsOf: destination), "previous file")
    }

    func testSuccessfulDownloadAndChecksum() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source")
        let destination = folder.appendingPathComponent("download.zip")
        try Data("abc".utf8).write(to: source)
        let delegate = DownloadDelegate(destinationURL: destination)
        var result: Result<URL, Error>?
        delegate.completionHandler = { result = $0 }
        let response = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)
        delegate.finishDownload(at: source, response: response)
        XCTAssertEqual(try result!.get(), destination)
        XCTAssertNoThrow(try verifyArtifact(at: destination, expectedDigest: digest))
        XCTAssertThrowsError(try verifyArtifact(at: destination, expectedDigest: String(repeating: "0", count: 64)))
    }
}
