import SwiftUI

struct UpdateView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var updater: UpdateChecker
    
    var body: some View {
        VStack(spacing: 20) {
            // App Icon
            if let appIcon = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
            }
            
            // Title and Version
            VStack(spacing: 4) {
                Text(updater.updateAvailable ? "Update Available" : "Up to Date")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                if let version = updater.latestVersion {
                    Text("Version \(version)")
                        .foregroundStyle(.secondary)
                }
            }
            
            // Release Notes
            if updater.updateAvailable, let notes = updater.releaseNotes {
                ScrollView {
                    Text(notes)
                        .font(.system(.body))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .frame(maxHeight: 200)
                .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            // Action Buttons
            HStack(spacing: 12) {
                if updater.updateAvailable {
                    Button("Later") {
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    
                    Button {
                        if let url = updater.downloadURL {
                            NSWorkspace.shared.open(url)
                            dismiss()
                        }
                    } label: {
                        Text("Download Update")
                            .frame(width: 120)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("OK") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            
            if updater.isChecking {
                ProgressView()
                    .scaleEffect(0.8)
                    .padding(.top, 8)
            }
        }
        .padding(30)
        .frame(width: 400)
        .background(VisualEffectBlur(material: .contentBackground, blendingMode: .behindWindow))
    }
} 