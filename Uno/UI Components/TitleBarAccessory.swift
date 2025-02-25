import SwiftUI

struct TitleBarAccessory: View {
    @AppStorage("isDarkMode") private var isDarkMode = false
    @State private var isHovering = false
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isDarkMode.toggle()
            }
        }) {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(isHovering ? 0.1 : 0))
                    .frame(width: 28, height: 28)
                
                Image(systemName: isDarkMode ? "sun.max.fill" : "moon.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 34, height: 34)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
        .help(isDarkMode ? "Switch to Light Mode" : "Switch to Dark Mode")
    }
}