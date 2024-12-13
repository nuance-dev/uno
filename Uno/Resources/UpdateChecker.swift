import Foundation
import os.log

private let logger = Logger(subsystem: "me.nuanc.Uno", category: "UpdateChecker")

struct GitHubRelease: Codable {
    let tagName: String
    let name: String
    let body: String
    let htmlUrl: String
    
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlUrl = "html_url"
    }
}

class UpdateChecker: ObservableObject {
    @Published var updateAvailable = false
    @Published var latestVersion: String?
    @Published var releaseNotes: String?
    @Published var downloadURL: URL?
    @Published var isChecking = false
    @Published var error: String?
    @Published var statusIcon: String = "checkmark.circle"
    @Published var isProcessing = false
    
    var onStatusChange: ((String) -> Void)?
    var onUpdateAvailable: (() -> Void)?
    
    private let currentVersion: String
    private let githubRepo: String
    private var updateCheckTimer: Timer?
    private var retryCount = 0
    private let maxRetries = 3
    private let performanceMonitor = PerformanceMonitor.shared
    
    init() {
        self.currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        self.githubRepo = "nuance-dev/uno"
        setupTimer()
        updateStatusIcon()
    }
    
    private func setupTimer() {
        // Initial check after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.checkForUpdates()
        }
        
        // Periodic check every 24 hours
        updateCheckTimer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            self?.checkForUpdates()
        }
    }
    
    private func updateStatusIcon() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.isChecking {
                self.statusIcon = "arrow.triangle.2.circlepath"
            } else {
                self.statusIcon = self.updateAvailable ? "exclamationmark.circle" : "checkmark.circle"
            }
            self.onStatusChange?(self.statusIcon)
        }
    }
    
    func checkForUpdates() {
        performanceMonitor.trackOperation("checkForUpdates") {
            guard !isChecking else { return }
            
            isChecking = true
            updateStatusIcon()
            error = nil
            
            let request = createUpdateRequest()
            performNetworkRequest(request)
        }
    }
    
    private func performNetworkRequest(_ request: URLRequest) {
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            self?.performanceMonitor.trackOperation("handleUpdateResponse") {
                DispatchQueue.main.async {
                    if let error = error {
                        self?.handleNetworkError(error)
                    } else {
                        self?.handleUpdateResponse(data: data, response: response as? HTTPURLResponse)
                    }
                }
            }
        }
        task.resume()
    }
    
    private func handleNetworkError(_ error: Error) {
        if retryCount < maxRetries {
            retryCount += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(retryCount * 2)) {
                self.checkForUpdates()
            }
        } else {
            retryCount = 0
            self.error = "Network error: \(error.localizedDescription)"
            self.isChecking = false
            self.updateStatusIcon()
        }
    }
    
    private func handleUpdateResponse(data: Data?, response: HTTPURLResponse?) {
        defer {
            DispatchQueue.main.async { [weak self] in
                self?.isChecking = false
                self?.updateStatusIcon()
            }
        }
        
        guard let response = response, 
              response.statusCode == 200,
              let data = data else {
            let errorMessage = "Invalid response from server"
            logger.error("\(errorMessage)")
            handleError(NSError(domain: "UpdateChecker",
                              code: response?.statusCode ?? -1,
                              userInfo: [NSLocalizedDescriptionKey: errorMessage]))
            return
        }
        
        do {
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            DispatchQueue.main.async { [weak self] in
                self?.processRelease(release)
            }
        } catch {
            handleError(error)
        }
    }
    
    private func processRelease(_ release: GitHubRelease) {
        let cleanLatestVersion = release.tagName.replacingOccurrences(of: "v", with: "")
        print("Latest version: \(cleanLatestVersion)")
        print("Current version for comparison: \(currentVersion)")
        
        updateAvailable = compareVersions(current: currentVersion, latest: cleanLatestVersion)
        if updateAvailable {
            DispatchQueue.main.async {
                self.onUpdateAvailable?()
            }
        }
        
        latestVersion = cleanLatestVersion
        releaseNotes = release.body
        downloadURL = URL(string: release.htmlUrl)
        
        print("Update available: \(updateAvailable)")
    }
    
    private func compareVersions(current: String, latest: String) -> Bool {
        // Clean and split versions
        let currentParts = current.replacingOccurrences(of: "v", with: "")
            .split(separator: ".")
            .compactMap { Int($0) }
        
        let latestParts = latest.replacingOccurrences(of: "v", with: "")
            .split(separator: ".")
            .compactMap { Int($0) }
        
        
        // Ensure we have at least 3 components (major.minor.patch)
        let paddedCurrent = currentParts + Array(repeating: 0, count: max(3 - currentParts.count, 0))
        let paddedLatest = latestParts + Array(repeating: 0, count: max(3 - latestParts.count, 0))
        
        
        // Compare each version component
        for i in 0..<min(paddedCurrent.count, paddedLatest.count) {
            if paddedLatest[i] > paddedCurrent[i] {
                return true
            } else if paddedLatest[i] < paddedCurrent[i] {
                return false
            }
        }
        
        print("Versions are equal")
        return false
    }
    
    private func createUpdateRequest() -> URLRequest {
        let url = URL(string: "https://api.github.com/repos/\(githubRepo)/releases/latest")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        return request
    }
    
    private func handleError(_ error: Error?) {
        let errorMessage = error?.localizedDescription ?? "Unknown error occurred"
        logger.error("Update check error: \(errorMessage)")
        DispatchQueue.main.async {
            self.error = errorMessage
            self.isChecking = false
            self.updateStatusIcon()
        }
    }
    
    deinit {
        updateCheckTimer?.invalidate()
    }
}
