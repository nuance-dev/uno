import SwiftUI

struct UpdateView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var updater: UpdateChecker
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
            
            Text(updater.updateAvailable ? "Update Available" : "No Updates Available")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(updater.updateAvailable ? 
                "A new version of Uno is available. Would you like to download it now?" :
                "You're running the latest version of Uno.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            
            if updater.updateAvailable {
                HStack(spacing: 12) {
                    Button("Later") {
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    
                    Button {
                        if let url = updater.downloadURL {
                            NSWorkspace.shared.open(url)
                        }
                        dismiss()
                    } label: {
                        Text("Download")
                            .frame(width: 100)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
            } else {
                Button("OK") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
        }
        .padding(30)
        .frame(width: 400)
    }
} 