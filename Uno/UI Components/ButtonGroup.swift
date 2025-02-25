import SwiftUI

struct ToolbarButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    let isFirst: Bool
    let isLast: Bool
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .frame(height: 36)
            .padding(.horizontal, 16)
            .foregroundColor(isHovering ? .primary : .secondary)
            .background(
                RoundedRectangle(cornerRadius: isFirst ? 8 : isLast ? 8 : 0)
                    .fill(Color.primary.opacity(isHovering ? 0.1 : 0))
                    .mask(
                        HStack(spacing: 0) {
                            if isFirst {
                                Rectangle()
                                    .frame(width: 100)
                                Spacer(minLength: 0)
                            } else if isLast {
                                Spacer(minLength: 0)
                                Rectangle()
                                    .frame(width: 100)
                            } else {
                                Rectangle()
                            }
                        }
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
}

struct ButtonDivider: View {
    var body: some View {
        Divider()
            .frame(height: 20)
            .opacity(0.3)
    }
}

struct ButtonGroup: View {
    let buttons: [(title: String, icon: String, action: () -> Void)]
    @Environment(\.colorScheme) private var colorScheme
    
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
        .background(backgroundView)
        .animation(.easeInOut(duration: 0.2), value: buttons.count)
    }
    
    private var backgroundView: some View {
        ZStack {
            // Base background with subtle blur
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    colorScheme == .dark ?
                        Color(NSColor.windowBackgroundColor).opacity(0.7) :
                        Color(NSColor.windowBackgroundColor).opacity(0.8)
                )
            
            // Subtle border
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    colorScheme == .dark ?
                        Color.white.opacity(0.08) :
                        Color.black.opacity(0.05),
                    lineWidth: 1
                )
                
            // Subtle shadow for depth
            if colorScheme == .light {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
                    .blur(radius: 0.5)
                    .offset(x: 0, y: 0.5)
            }
        }
        .shadow(
            color: colorScheme == .dark ?
                Color.black.opacity(0.2) :
                Color.black.opacity(0.05),
            radius: 5,
            x: 0,
            y: 2
        )
    }
}
