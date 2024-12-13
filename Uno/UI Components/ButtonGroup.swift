import SwiftUI
import AppKit

struct ToolbarButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    let isFirst: Bool
    let isLast: Bool
    
    @State private var isHovered = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(height: 32)
            .background(
                ZStack {
                    if isHovered {
                        RoundedRectangle(cornerRadius: isFirst ? 12 : isLast ? 12 : 0)
                            .fill(Color.primary.opacity(0.06))
                    }
                }
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hover in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hover
            }
        }
    }
}

struct ButtonDivider: View {
    var body: some View {
        Rectangle()
            .frame(width: 1)
            .foregroundColor(Color.primary.opacity(0.1))
    }
}

struct ButtonGroup: View {
    let buttons: [(title: String, icon: String, action: () -> Void)]
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(buttons.enumerated()), id: \.offset) { index, button in
                if index > 0 {
                    ButtonDivider()
                }
                
                ToolbarButton(
                    title: button.title,
                    icon: button.icon,
                    action: button.action,
                    isFirst: index == 0,
                    isLast: index == buttons.count - 1
                )
            }
        }
        .background(
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.05 : 0.02))
                
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.1 : 0.05), lineWidth: 0.5)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
