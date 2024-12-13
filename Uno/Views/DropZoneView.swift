import SwiftUI

struct DropZoneView: View {
    @Binding var isDragging: Bool
    let mode: ContentView.Mode
    let onTap: () -> Void
    @State private var isHovered = false
    @State private var pulseAnimation = false
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 24) {
                // Animated icon
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.1))
                        .frame(width: 80, height: 80)
                        .scaleEffect(pulseAnimation ? 1.1 : 0.9)
                        .opacity(pulseAnimation ? 0.6 : 0.3)
                    
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(
                            .linearGradient(
                                colors: [.accentColor, .accentColor.opacity(0.7)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .offset(y: isDragging ? 5 : 0)
                }
                
                VStack(spacing: 8) {
                    Text(mode == .prompt ? 
                         "Drop files or folders to create a prompt" :
                         "Drop files to create a PDF")
                        .font(.title3.weight(.medium))
                        .foregroundColor(.primary.opacity(0.8))
                    
                    Text(mode == .prompt ?
                         "Supports: Code, docs, config files, and more" :
                         "Supports: Most document formats and images")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(isDragging ? 0.8 : 0.3),
                                Color.accentColor.opacity(isDragging ? 0.6 : 0.1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        style: StrokeStyle(
                            lineWidth: isDragging ? 2 : 1,
                            dash: [10]
                        )
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.primary.opacity(0.03))
                    )
            )
            .padding()
            .scaleEffect(isHovered ? 0.995 : 1)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hover in
            withAnimation(.spring(response: 0.3)) {
                isHovered = hover
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulseAnimation = true
            }
        }
    }
}
