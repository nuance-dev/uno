import SwiftUI

struct GlassButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(configuration.isPressed ? 0.15 : 0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.accentColor.opacity(configuration.isPressed ? 0.3 : 0.2), lineWidth: 1)
                    )
                    .shadow(
                        color: colorScheme == .dark ? 
                            Color.accentColor.opacity(configuration.isPressed ? 0.2 : 0.1) : 
                            Color.black.opacity(0.03),
                        radius: configuration.isPressed ? 2 : 4,
                        x: 0,
                        y: configuration.isPressed ? 1 : 2
                    )
            )
            .foregroundColor(Color.accentColor)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// Preview a button with this style
struct GlassButtonStyle_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            Button("Primary Action") {}
                .buttonStyle(GlassButtonStyle())
            
            Button(action: {}) {
                Label("With Icon", systemImage: "arrow.down.doc")
            }
            .buttonStyle(GlassButtonStyle())
        }
        .padding()
        .preferredColorScheme(.dark)
    }
}
