import SwiftUI

struct LoaderView: View {
    @State private var isAnimating = false
    private let duration: Double = 1.5
    
    var body: some View {
        ZStack {
            // Backdrop blur
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            
            // Modern spinner container
            ZStack {
                // Background card
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(NSColor.windowBackgroundColor).opacity(0.7))
                    .frame(width: 120, height: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.black.opacity(0.2))
                            .blur(radius: 10)
                    )
                
                // Spinner rings
                ZStack {
                    // Outer ring
                    Circle()
                        .trim(from: 0.2, to: 0.8)
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [Color.clear, Color.accentColor.opacity(0.3)]),
                                center: .center,
                                startAngle: .degrees(0),
                                endAngle: .degrees(360)
                            ),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 54, height: 54)
                        .rotationEffect(.degrees(isAnimating ? 360 : 0))
                    
                    // Inner ring
                    Circle()
                        .trim(from: 0, to: 0.6)
                        .stroke(
                            Color.accentColor,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 38, height: 38)
                        .rotationEffect(.degrees(isAnimating ? 360 : 0))
                    
                    // Label
                    Text("Processing")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                        .offset(y: 46)
                }
            }
        }
        .onAppear {
            withAnimation(
                .linear(duration: duration)
                .repeatForever(autoreverses: false)
            ) {
                isAnimating = true
            }
        }
    }
}

#Preview {
    LoaderView()
        .frame(width: 400, height: 400)
}
