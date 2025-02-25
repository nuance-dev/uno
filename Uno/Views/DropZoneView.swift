import SwiftUI

struct DropZoneView: View {
    @Binding var isDragging: Bool
    let mode: ContentView.Mode
    let onButtonClick: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // App logo & title
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.1))
                        .frame(width: 84, height: 84)
                    
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 36))
                        .foregroundColor(.accentColor)
                }
                
                Text("Uno")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.primary)
                
                Text(mode == .prompt ? "Code to Prompt Converter" : "Code to PDF Converter")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Drop zone
            VStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.accentColor.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(
                                    isDragging ? Color.accentColor : Color.secondary.opacity(0.2),
                                    style: StrokeStyle(lineWidth: isDragging ? 2 : 1, dash: isDragging ? [] : [6, 6])
                                )
                        )
                        .shadow(color: isDragging ? Color.accentColor.opacity(0.2) : .clear, radius: 10, x: 0, y: 0)
                    
                    VStack(spacing: 20) {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 32))
                            .foregroundColor(isDragging ? .accentColor : .secondary)
                            .opacity(isDragging ? 1 : 0.8)
                        
                        Text("Drop files here")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(isDragging ? .accentColor : .primary)
                        
                        Text("or")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        
                        Button(action: onButtonClick) {
                            Text("Select Files")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.accentColor)
                                .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .scaleEffect(isHovering ? 1.02 : 1.0)
                        .brightness(isHovering ? 0.05 : 0)
                        .onHover { hovering in
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                                isHovering = hovering
                            }
                        }
                    }
                    .padding(40)
                }
                .frame(maxWidth: 380, maxHeight: 280)
                
                // Supported file types
                HStack(spacing: 5) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Text(supportedTypesText)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                }
                .padding(.top, 4)
            }
            
            Spacer()
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: isDragging)
    }
    
    private var supportedTypesText: String {
        if mode == .prompt {
            return "Code files, text files, and data files"
        } else {
            return "Code files, text files, PDFs, and images"
        }
    }
}
