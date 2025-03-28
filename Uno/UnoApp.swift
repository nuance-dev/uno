import SwiftUI
import AppKit
import UserNotifications

@main
struct UnoApp: App {
    @StateObject private var updater = UpdateChecker()
    @State private var showingUpdateSheet = false
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(updater)
                .sheet(isPresented: $showingUpdateSheet) {
                    UpdateView(updater: updater)
                }
                .task {
                    await updater.checkForUpdates()
                    if updater.updateAvailable {
                        showingUpdateSheet = true
                    }
                    updater.scheduleRecurringChecks()
                }
                .background(VisualEffectBackground())
                .preferredColorScheme(.dark) // Optional: Force dark mode for modern look
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    Task {
                        await updater.checkForUpdates()
                        showingUpdateSheet = true
                    }
                }
                .keyboardShortcut("U", modifiers: [.command])
                
                if updater.updateAvailable, let url = updater.downloadURL {
                    Button("Download Update") {
                        NSWorkspace.shared.open(url)
                    }
                }
                
                Divider()
            }
        }
    }
}

// Background effect that works with transparent windows
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .underWindowBackground
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
