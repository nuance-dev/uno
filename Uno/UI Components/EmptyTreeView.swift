import SwiftUI

struct EmptyTreeView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No files selected")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
} 