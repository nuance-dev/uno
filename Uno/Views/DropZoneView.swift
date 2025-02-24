import SwiftUI

struct DropZoneView: View {
    @Binding var isDragging: Bool
    let mode: ContentView.Mode
    let onTap: () -> Void
    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 20) {
                // Icon
                ZStack {
                    // Circle background
                    Circle()
                        .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.15 : 0.2))
                        .frame(width: 80, height: 80)
                    
                    // Outer ring
                    Circle()
                        .strokeBorder(
                            Color.accentColor.opacity(colorScheme == .dark ? 0.5 : 0.7),
                            lineWidth: isDragging ? 3 : 2
                        )
                        .frame(width: 80, height: 80)
                        .scaleEffect(isDragging ? 1.1 : 1.0)
                    
                    // Mode-specific icon
                    Image(systemName: mode == .prompt ? "text.alignleft" : "doc.richtext")
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(Color.accentColor)
                        .rotationEffect(.degrees(isDragging ? 8 : 0))
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isDragging)
                
                // Main title
                Text(mode == .prompt ? 
                     "Drop files to create a prompt" :
                     "Drop files to create a PDF")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(
                        isDragging ? Color.accentColor : Color.primary
                    )
                
                // Subtitle
                Text(mode == .prompt ?
                     "Supports code, docs, images, and more" :
                     "Combines multiple files into a single document")
                    .font(.body)
                    .foregroundColor(.primary.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                    .opacity(isDragging ? 0.7 : 1.0)
                
                // Chip showing supported file types
                Text(mode == .prompt ?
                     "TXT • MD • CODE • PDF • JSON • YAML • XML" :
                     "PDF • TXT • IMAGES • CODE • HTML")
                    .font(.caption)
                    .foregroundColor(.primary.opacity(0.7))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(
                                Color.secondary.opacity(isHovering ? 
                                    (colorScheme == .dark ? 0.2 : 0.15) : 
                                    (colorScheme == .dark ? 0.15 : 0.1))
                            )
                    )
                    .padding(.top, 4)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .background(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    isDragging ? 
                        Color.accentColor.opacity(colorScheme == .dark ? 0.6 : 0.8) :
                        Color.secondary.opacity(isHovering ? 
                            (colorScheme == .dark ? 0.3 : 0.4) : 
                            (colorScheme == .dark ? 0.15 : 0.25)),
                    style: StrokeStyle(
                        lineWidth: isDragging ? 2.5 : (isHovering ? 1.5 : 1),
                        dash: isDragging ? [] : [6, 4]
                    )
                )
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.secondary.opacity(colorScheme == .dark ? 0.05 : 0.07))
                )
        )
        .animation(.easeInOut(duration: 0.2), value: isDragging)
        .animation(.easeInOut(duration: 0.2), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
