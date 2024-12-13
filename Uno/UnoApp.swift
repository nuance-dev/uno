import SwiftUI
import AppKit
import UserNotifications
@main
struct UnoApp: App {
    @AppStorage("isDarkMode") private var isDarkMode = false
    @StateObject private var updater = UpdateChecker()
    @State private var showingUpdateSheet = false
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(isDarkMode ? .dark : .light)
                .background(WindowAccessor())
                .sheet(isPresented: $showingUpdateSheet) {
                    UpdateView(updater: updater)
                }
                .onAppear {
                    updater.checkForUpdates()
                    updater.onUpdateAvailable = {
                        showingUpdateSheet = true
                    }
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
                        if let error = error {
                            print("Error requesting notification permission: \(error.localizedDescription)")
                        }
                    }
                }
        }
        .windowStyle(HiddenTitleBarWindowStyle())
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    showingUpdateSheet = true
                    updater.checkForUpdates()
                }
                .keyboardShortcut("U", modifiers: [.command])
                
                if updater.updateAvailable {
                    Button("Download Update") {
                        if let url = updater.downloadURL {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                
                Divider()
            }
        }
    }
}
