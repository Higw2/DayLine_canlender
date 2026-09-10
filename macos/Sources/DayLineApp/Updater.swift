import AppKit
import CryptoKit
import DayLineCore
import Foundation

struct AvailableUpdate: Identifiable, Equatable {
    let releaseID: Int64
    let tag: String
    let version: SemanticVersion
    let releaseName: String
    let notes: String
    let pageURL: URL
    let assetURL: URL
    let assetSize: Int64
    let digest: String

    var id: Int64 { releaseID }
}

private struct GitHubRelease: Decodable {
    let id: Int64
    let tagName: String
    let name: String?
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let htmlURL: URL
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case id, name, body, draft, prerelease, assets
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

private struct GitHubAsset: Decodable {
    let name: String
    let size: Int64
    let digest: String?
    let downloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name, size, digest
        case downloadURL = "browser_download_url"
    }
}

private enum UpdateError: LocalizedError {
    case invalidConfiguration
    case invalidResponse
    case releaseMissingChecksum
    case checksumMismatch
    case invalidArchive
    case wrongBundleIdentifier
    case wrongVersion
    case invalidSignature
    case appNotPackaged
    case appDirectoryNotWritable
    case helperMissing
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: return "更新服务配置无效"
        case .invalidResponse: return "GitHub 返回了无效的更新信息"
        case .releaseMissingChecksum: return "Release 安装包缺少 SHA-256 摘要，已取消安装"
        case .checksumMismatch: return "下载包的 SHA-256 校验失败，已取消安装"
        case .invalidArchive: return "下载包中没有有效的 DayLine.app"
        case .wrongBundleIdentifier: return "下载包不是官方 DayLine macOS 应用"
        case .wrongVersion: return "下载包版本与 Release 版本不一致"
        case .invalidSignature: return "下载应用的代码签名校验失败"
        case .appNotPackaged: return "请从 DayLine.app 中运行后再执行应用内更新"
        case .appDirectoryNotWritable: return "DayLine.app 所在目录不可写，请将应用移到“应用程序”文件夹后重试"
        case .helperMissing: return "应用包缺少更新辅助程序，请重新构建 DayLine.app"
        case .commandFailed(let command): return "\(command) 执行失败"
        }
    }
}

@MainActor
final class UpdateController: ObservableObject {
    @Published private(set) var availableUpdate: AvailableUpdate?
    @Published private(set) var isChecking = false
    @Published private(set) var isInstalling = false
    @Published private(set) var statusText = "尚未检查更新"
    @Published private(set) var lastCheckedAt: Date?
    @Published var shouldPresentUpdateAlert = false

    private let session: URLSession
    private let defaults: UserDefaults
    private var settingsProvider: (() -> AppSettings)?
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?

    private static let lastCheckKey = "DayLineUpdater.lastCheck"
    private static let maximumAssetSize: Int64 = 500 * 1_024 * 1_024

    init(session: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.session = session
        self.defaults = defaults
        lastCheckedAt = defaults.object(forKey: Self.lastCheckKey) as? Date
    }

    deinit {
        timer?.invalidate()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }

    var installedVersionText: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
    }

    func configure(settingsProvider: @escaping () -> AppSettings) {
        self.settingsProvider = settingsProvider
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.checkIfDue() }
        }
        reschedule()
        checkIfDue()
    }

    func settingsDidChange() {
        reschedule()
        checkIfDue()
    }

    func checkNow() {
        check(manual: true)
    }

    func installAvailableUpdate() {
        guard let release = availableUpdate, !isInstalling else { return }
        isInstalling = true
        statusText = "正在下载 DayLine \(release.version)…"

        Task {
            do {
                let stagedApp = try await downloadAndValidate(release)
                try launchInstaller(stagedApp: stagedApp)
                statusText = "更新已就绪，DayLine 将重新启动…"
                NSApp.terminate(nil)
            } catch {
                isInstalling = false
                statusText = "更新失败：\(error.localizedDescription)"
            }
        }
    }

    func openReleasePage() {
        guard let pageURL = availableUpdate?.pageURL else { return }
        NSWorkspace.shared.open(pageURL)
    }

    private func reschedule() {
        timer?.invalidate()
        timer = nil
        guard let settings = settingsProvider?(), settings.automaticUpdatesEnabled else { return }
        timer = Timer.scheduledTimer(withTimeInterval: settings.updateCheckInterval.seconds, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check(manual: false) }
        }
    }

    private func checkIfDue() {
        guard let settings = settingsProvider?(), settings.automaticUpdatesEnabled else { return }
        let elapsed = Date().timeIntervalSince(lastCheckedAt ?? .distantPast)
        if elapsed >= settings.updateCheckInterval.seconds { check(manual: false) }
    }

    private func check(manual: Bool) {
        guard !isChecking, !isInstalling else { return }
        guard let endpoint = releasesEndpoint() else {
            statusText = UpdateError.invalidConfiguration.localizedDescription
            return
        }

        isChecking = true
        statusText = "正在检查更新…"
        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("DayLine/\(installedVersionText)", forHTTPHeaderField: "User-Agent")

        Task {
            defer { isChecking = false }
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw UpdateError.invalidResponse }
                let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
                let candidate = try selectUpdate(from: releases)
                let now = Date()
                lastCheckedAt = now
                defaults.set(now, forKey: Self.lastCheckKey)
                availableUpdate = candidate
                if let candidate {
                    statusText = "发现新版本 \(candidate.version)"
                    shouldPresentUpdateAlert = !manual
                } else {
                    statusText = "已是最新版本（\(installedVersionText)）"
                }
            } catch {
                statusText = "检查失败：\(error.localizedDescription)"
            }
        }
    }

    private func releasesEndpoint() -> URL? {
        guard let owner = Bundle.main.object(forInfoDictionaryKey: "DLUpdateRepositoryOwner") as? String,
              let repository = Bundle.main.object(forInfoDictionaryKey: "DLUpdateRepositoryName") as? String else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = "/repos/\(owner)/\(repository)/releases"
        components.queryItems = [URLQueryItem(name: "per_page", value: "20")]
        return components.url
    }

    private func selectUpdate(from releases: [GitHubRelease]) throws -> AvailableUpdate? {
        let bundle = Bundle.main
        let currentTag = bundle.object(forInfoDictionaryKey: "DLCurrentReleaseTag") as? String
        let assetName = bundle.object(forInfoDictionaryKey: "DLUpdateAssetName") as? String ?? "DayLine-macOS.zip"

        var candidates: [AvailableUpdate] = []
        for release in releases {
            guard !release.draft, !release.prerelease,
                  let version = UpdateVersionPolicy.newerVersion(
                    releaseTag: release.tagName,
                    releaseName: release.name,
                    installedVersion: installedVersionText,
                    currentReleaseTag: currentTag
                  ),
                  let asset = release.assets.first(where: { $0.name == assetName }),
                  asset.size > 0, asset.size <= Self.maximumAssetSize else { continue }
            guard let digest = asset.digest, isValidSHA256(digest) else { throw UpdateError.releaseMissingChecksum }
            candidates.append(AvailableUpdate(
                releaseID: release.id,
                tag: release.tagName,
                version: version,
                releaseName: release.name ?? release.tagName,
                notes: release.body ?? "",
                pageURL: release.htmlURL,
                assetURL: asset.downloadURL,
                assetSize: asset.size,
                digest: digest
            ))
        }
        return candidates.max { $0.version < $1.version }
    }

    private func downloadAndValidate(_ release: AvailableUpdate) async throws -> URL {
        guard release.assetURL.scheme == "https", release.assetURL.host?.lowercased() == "github.com" else {
            throw UpdateError.invalidConfiguration
        }
        let (temporaryArchive, response) = try await session.download(from: release.assetURL)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw UpdateError.invalidResponse }
        let attributes = try FileManager.default.attributesOfItem(atPath: temporaryArchive.path)
        let actualSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard actualSize == release.assetSize else { throw UpdateError.checksumMismatch }
        guard try sha256(of: temporaryArchive) == release.digest.dropFirst("sha256:".count).lowercased() else {
            throw UpdateError.checksumMismatch
        }

        let stage = FileManager.default.temporaryDirectory.appendingPathComponent("DayLine-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        try run("/usr/bin/ditto", ["-x", "-k", temporaryArchive.path, stage.path])
        let app = stage.appendingPathComponent("DayLine.app", isDirectory: true)
        guard FileManager.default.fileExists(atPath: app.path), let stagedBundle = Bundle(url: app) else { throw UpdateError.invalidArchive }
        guard stagedBundle.bundleIdentifier == Bundle.main.bundleIdentifier else { throw UpdateError.wrongBundleIdentifier }
        let stagedVersionText = stagedBundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        guard SemanticVersion(parsing: stagedVersionText) == release.version else { throw UpdateError.wrongVersion }
        do { try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]) }
        catch { throw UpdateError.invalidSignature }
        return app
    }

    private func launchInstaller(stagedApp: URL) throws {
        let installedApp = Bundle.main.bundleURL.standardizedFileURL
        guard installedApp.pathExtension == "app" else { throw UpdateError.appNotPackaged }
        guard FileManager.default.isWritableFile(atPath: installedApp.deletingLastPathComponent().path) else {
            throw UpdateError.appDirectoryNotWritable
        }
        guard let helper = Bundle.main.resourceURL?.appendingPathComponent("DayLineUpdaterHelper"),
              FileManager.default.isExecutableFile(atPath: helper.path) else { throw UpdateError.helperMissing }

        let process = Process()
        process.executableURL = helper
        process.arguments = [installedApp.path, stagedApp.path, String(ProcessInfo.processInfo.processIdentifier)]
        try process.run()
    }

    private func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError.commandFailed(executable) }
    }

    private func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1_048_576) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func isValidSHA256(_ digest: String) -> Bool {
        digest.range(of: #"^sha256:[0-9a-fA-F]{64}$"#, options: .regularExpression) != nil
    }
}
