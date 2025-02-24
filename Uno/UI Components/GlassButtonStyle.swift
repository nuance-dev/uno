import SwiftUI

struct GlassButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.15 : 0.25))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.accentColor.opacity(colorScheme == .dark ? 0.3 : 0.4), lineWidth: 1)
                    )
            )
            .foregroundColor(Color.accentColor)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}
