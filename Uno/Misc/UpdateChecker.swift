// UpdateChecker.swift
import Foundation
import os // Use Logger

private let logger = Logger(subsystem: "me.nuanc.Uno", category: "UpdateChecker")

// GitHubRelease struct remains the same
struct GitHubRelease: Codable {
    let tagName: String
    let name: String
    let body: String?
    let htmlUrl: String
    let publishedAt: String // Or Date if using dateDecodingStrategy
}

@MainActor // Ensure published properties are updated on main thread
class UpdateChecker: ObservableObject {
    @Published var updateAvailable = false
    @Published var latestVersion: String?
    @Published var releaseNotes: String?
    @Published var downloadURL: URL?
    @Published var isChecking = false
    @Published var error: String?
    // Removed: @Published var statusIcon: String = "checkmark.circle"
    // Removed: var onStatusChange: ((String) -> Void)?

    // Keep onUpdateAvailable if used by App struct
    var onUpdateAvailable: (() -> Void)?

    private let currentVersion: String
    private let githubRepo: String
    private var updateCheckTimer: Timer?
    private var initialCheckTask: Task<Void, Never>?


    init(githubRepo: String = "nuance-dev/Uno") { // Allow repo override
        self.currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        self.githubRepo = githubRepo
        logger.info("UpdateChecker initialized. Current version: \(self.currentVersion), Repo: \(self.githubRepo)")
        // Don't start timer immediately, let app lifecycle handle initial check
        // setupTimer()
    }

    func scheduleRecurringChecks(interval: TimeInterval = 24 * 60 * 60) {
         // Invalidate existing timer if any
         updateCheckTimer?.invalidate()
         logger.info("Scheduling recurring update check every \(interval / 3600) hours.")
         // Run first check shortly after scheduling (moved to .task in UnoApp)
         // DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
         //      Task { await self?.checkForUpdates() }
         // }
         // Schedule repeating timer
         updateCheckTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
             logger.debug("Performing scheduled update check.")
             Task { await self?.checkForUpdates() }
         }
     }

     deinit {
         updateCheckTimer?.invalidate()
         initialCheckTask?.cancel()
         logger.info("UpdateChecker deinitialized.")
     }


    // Make check async
    func checkForUpdates() async {
        guard !isChecking else {
            logger.debug("Update check already in progress.")
            return
        }

        logger.info("Checking for updates...")
        isChecking = true
        error = nil // Clear previous error

        let baseURL = "https://api.github.com/repos/\(githubRepo)/releases/latest"
        guard let url = URL(string: baseURL) else {
            logger.error("Invalid GitHub repository URL: \(baseURL)")
            error = "Internal Error: Invalid repository URL"
            isChecking = false
            return
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15.0) // Add timeout
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept") // Updated Accept header
        // request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept") // This might be redundant
        request.setValue("Uno-App/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        // TODO: Consider adding a GitHub token if rate limits become an issue
        // if let token = ProcessInfo.processInfo.environment["GITHUB_TOKEN"] {
        //     request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        // }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            handleUpdateResponse(data: data, response: response as? HTTPURLResponse)
        } catch {
            logger.error("Network error during update check: \(error.localizedDescription)")
            if let urlError = error as? URLError, urlError.code == .timedOut {
                 self.error = "Update check timed out. Please check your connection."
             } else {
                 self.error = "Network Error: \(error.localizedDescription)"
             }
            isChecking = false
        }
    }

    private func handleUpdateResponse(data: Data?, response: HTTPURLResponse?) {
        // Ensure isChecking is set to false eventually
         defer { isChecking = false }

        guard let response = response else {
            logger.error("Invalid response received (nil).")
            error = "Invalid response from server."
            return
        }

        logger.debug("Update check response status code: \(response.statusCode)")

        guard (200..<300).contains(response.statusCode) else {
             logger.error("Server returned error status: \(response.statusCode)")
             error = "Server Error (\(response.statusCode)). Could not check for updates."
             // Handle specific codes like 404 (repo not found) or 403 (rate limited) if needed
             if response.statusCode == 404 { error = "Repository not found. Update check failed."} // Corrected message
             if response.statusCode == 403 { error = "API rate limit exceeded. Please try again later."} // Corrected message
             return
        }

        guard let data = data else {
            logger.error("No data received in update response.")
            error = "No data received from server."
            return
        }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase // Match GitHub's snake_case keys
            // decoder.dateDecodingStrategy = .iso8601 // If parsing dates, ensure `publishedAt` is Date
            let release = try decoder.decode(GitHubRelease.self, from: data)

            let cleanLatestVersion = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            logger.info("Latest version found: \(cleanLatestVersion)")

            // Use robust version comparison
            let comparisonResult = currentVersion.compare(cleanLatestVersion, options: .numeric)
            let newUpdateAvailable = comparisonResult == .orderedAscending

            // Update properties only if there's a change or initial state
             let shouldNotify = newUpdateAvailable && !updateAvailable // Notify only when transitioning to update available

             latestVersion = cleanLatestVersion
             releaseNotes = release.body
             // Ensure htmlUrl is a valid URL
             if let url = URL(string: release.htmlUrl) {
                 downloadURL = url
             } else {
                 logger.warning("Invalid download URL received from GitHub: \(release.htmlUrl)")
                 downloadURL = nil
             }
             updateAvailable = newUpdateAvailable

             if shouldNotify {
                 logger.notice("New update available: \(cleanLatestVersion)")
                 onUpdateAvailable?() // Trigger callback only on new discovery
             } else if !newUpdateAvailable {
                 logger.info("App is up to date (Current: \(self.currentVersion), Latest: \(cleanLatestVersion)).")
             }

            // Clear error on successful check
             error = nil

        } catch {
            logger.error("Failed to parse update response JSON: \(error.localizedDescription)")
            self.error = "Failed to process update information."
        }
    }

    // Version comparison logic removed, using String.compare(_:options:) instead.
} 