import SwiftUI

struct LoaderView: View {
    let progress: Double
    @State private var rotation: Double = 0
    @State private var showingIndeterminate: Bool = false
    
    var body: some View {
        ZStack {
            // Backdrop blur
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.95)
                .ignoresSafeArea()
            
            // Modern loader container
            VStack(spacing: 24) {
                // Animated loader
                ZStack {
                    // Track circle
                    Circle()
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 6)
                        .frame(width: 64, height: 64)
                    
                    // Progress circle with gradient
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.accentColor, Color.accentColor.opacity(0.8)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(
                                lineWidth: 6,
                                lineCap: .round
                            )
                        )
                        .frame(width: 64, height: 64)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut, value: progress)
                    
                    // Percentage text
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .opacity(showingIndeterminate ? 0 : 1)
                    
                    // Indeterminate spinner for initial load
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.accentColor, Color.accentColor.opacity(0.5)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(
                                lineWidth: 6,
                                lineCap: .round
                            )
                        )
                        .frame(width: 64, height: 64)
                        .rotationEffect(.degrees(rotation))
                        .opacity(showingIndeterminate ? 1 : 0)
                }
                
                VStack(spacing: 8) {
                    Text("Processing Files")
                        .font(.system(size: 16, weight: .semibold))
                    
                    Text("Creating your \(progress < 0.5 ? "content" : "output")")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            }
            .padding(36)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(NSColor.windowBackgroundColor).opacity(0.6))
                    .background(
                        VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: 10)
            )
        }
        .onAppear {
            // Start rotation animation for indeterminate spinner
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            
            // Show indeterminate spinner if progress is at 0%
            showingIndeterminate = progress == 0
            
            // Hide indeterminate spinner when progress starts
            if progress > 0 {
                withAnimation {
                    showingIndeterminate = false
                }
            }
        }
        .onChange(of: progress) { oldValue, newValue in
            if newValue > 0 && showingIndeterminate {
                withAnimation {
                    showingIndeterminate = false
                }
            }
        }
    }
}

#Preview {
    LoaderView(progress: 0.5)
        .frame(width: 400, height: 400)
}
