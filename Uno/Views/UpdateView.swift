// UpdateView.swift
import SwiftUI

struct UpdateView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var updater: UpdateChecker

    var body: some View {
        VStack(spacing: 16) { // Slightly reduced spacing
             Group { // Group content to apply common modifiers
                 if updater.isChecking {
                     ProgressView("Checking for updates...")
                         .padding(.vertical, 30) // Add padding when loading
                 } else if let error = updater.error {
                     Image(systemName: "exclamationmark.triangle.fill")
                         .font(.system(size: 40))
                         .foregroundStyle(.orange)
                     Text("Update Check Failed")
                         .font(.title3.weight(.semibold))
                     Text(error)
                         .font(.callout)
                         .multilineTextAlignment(.center)
                         .foregroundStyle(.secondary)
                         .padding(.horizontal)
                 } else if updater.updateAvailable, let latestVersion = updater.latestVersion {
                     Image(systemName: "arrow.down.circle.fill")
                         .font(.system(size: 40))
                         .foregroundStyle(.blue)
                     Text("Version \(latestVersion) Available")
                         .font(.title3.weight(.semibold))
                     // Optionally show release notes if available
                     if let notes = updater.releaseNotes, !notes.isEmpty {
                          ScrollView {
                              Text(notes)
                                  .font(.caption)
                                  .foregroundStyle(.secondary)
                                  .multilineTextAlignment(.leading) // Align left
                                  .frame(maxWidth: .infinity, alignment: .leading)
                          }
                          .frame(maxHeight: 100)
                          .padding(8)
                          .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                          .padding(.horizontal)

                     } else {
                          Text("A new version of Uno is available.")
                             .font(.callout)
                             .multilineTextAlignment(.center)
                             .foregroundStyle(.secondary)
                     }

                 } else {
                     Image(systemName: "checkmark.circle.fill")
                         .font(.system(size: 40))
                         .foregroundStyle(.green)
                     Text("Uno is Up To Date")
                          .font(.title3.weight(.semibold))
                     Text("You are running the latest version (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")).")
                         .font(.callout)
                         .multilineTextAlignment(.center)
                         .foregroundStyle(.secondary)
                 }
             }
             .padding(.bottom, 10) // Spacing before buttons

            actionButtons
        }
        .padding(25) // Overall padding
        .frame(minWidth: 380, maxWidth: 500) // Allow some width flexibility
         // Run check again when view appears if needed, or rely on manual trigger
         // .task { if !updater.isChecking { await updater.checkForUpdates() } }
    }

     @ViewBuilder
     private var actionButtons: some View {
         // Always show Check Again and Close unless checking
         if !updater.isChecking {
             HStack(spacing: 12) {
                 if updater.updateAvailable, let url = updater.downloadURL {
                      Button("Later") { dismiss() }
                         .keyboardShortcut(.cancelAction)

                      Button("Download") {
                         NSWorkspace.shared.open(url)
                         dismiss()
                     }
                     .buttonStyle(.borderedProminent)
                     .tint(.blue)
                     .keyboardShortcut(.defaultAction)

                 } else if updater.error != nil {
                     // Error state buttons
                      Button("Try Again") {
                         Task { await updater.checkForUpdates() }
                     }
                     .keyboardShortcut(.defaultAction)

                      Button("Close") { dismiss() }
                         .keyboardShortcut(.cancelAction)

                 } else {
                     // Up-to-date state button
                      Button("OK") { dismiss() }
                         .buttonStyle(.borderedProminent)
                         .tint(.blue)
                         .keyboardShortcut(.defaultAction)
                 }
             }
         }
     }
} 