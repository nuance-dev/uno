import SwiftUI

struct DropZoneView: View {
    @Binding var isDragging: Bool
    let mode: ContentView.Mode
    let onTap: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 20) {
                // Animated icon
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.1))
                        .frame(width: 80, height: 80)
                    
                    Circle()
                        .strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 2)
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: mode == .prompt ? "text.alignleft" : "doc.richtext")
                        .font(.system(size: 32))
                        .foregroundColor(.accentColor)
                }
                
                // Main title
                Text(mode == .prompt ? 
                     "Drop files to create a prompt" :
                     "Drop files to create a PDF")
                    .font(.title3.weight(.medium))
                    .foregroundColor(.primary)
                
                // Subtitle
                Text(mode == .prompt ?
                     "Supports code, docs, images, and more" :
                     "Combines multiple files into a single document")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                
                // Chip showing supported file types
                Text(mode == .prompt ?
                     "TXT • MD • CODE • PDF • JSON • YAML • XML" :
                     "PDF • TXT • IMAGES • CODE • HTML")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.secondary.opacity(0.1))
                    )
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isDragging ? Color.accentColor : (isHovering ? Color.secondary.opacity(0.2) : Color.clear),
                    style: StrokeStyle(
                        lineWidth: isDragging ? 2 : 1,
                        dash: isDragging ? [] : [6, 4]
                    )
                )
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.secondary.opacity(0.05))
                )
        )
        .animation(.easeInOut(duration: 0.2), value: isDragging)
        .animation(.easeInOut(duration: 0.2), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
