import SwiftUI

struct LoaderView: View {
    let progress: Double
    @State private var rotation: Double = 0
    @State private var showingIndeterminate: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            // Backdrop blur
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.95)
                .ignoresSafeArea()
            
            // Modern loader container
            VStack(spacing: 20) {
                // Animated loader
                ZStack {
                    // Track circle
                    Circle()
                        .stroke(
                            Color.secondary.opacity(colorScheme == .dark ? 0.15 : 0.1), 
                            lineWidth: 6
                        )
                        .frame(width: 70, height: 70)
                    
                    // Progress circle with gradient
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            Color.accentColor,
                            style: StrokeStyle(
                                lineWidth: 6,
                                lineCap: .round
                            )
                        )
                        .frame(width: 70, height: 70)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut, value: progress)
                    
                    // Percentage text
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .opacity(showingIndeterminate ? 0 : 1)
                    
                    // Indeterminate spinner for initial load
                    Circle()
                        .trim(from: 0, to: 0.65)
                        .stroke(
                            Color.accentColor,
                            style: StrokeStyle(
                                lineWidth: 6,
                                lineCap: .round
                            )
                        )
                        .frame(width: 70, height: 70)
                        .rotationEffect(.degrees(rotation))
                        .opacity(showingIndeterminate ? 1 : 0)
                }
                
                VStack(spacing: 8) {
                    Text(progress < 1.0 ? "Processing files..." : "Finishing up...")
                        .font(.system(size: 16, weight: .semibold))
                    
                    Text("Please wait while we prepare your content")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(colorScheme == .dark ? 
                          Color(red: 0.15, green: 0.15, blue: 0.15) : 
                          Color.white)
                    .opacity(0.95)
                    .shadow(
                        color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.1),
                        radius: 16,
                        x: 0,
                        y: 8
                    )
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
