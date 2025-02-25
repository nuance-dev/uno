import SwiftUI

struct LoaderView: View {
    let progress: Double
    @State private var rotation: Double = 0
    @State private var showingIndeterminate: Bool = false
    
    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            // Modern loader container
            VStack(spacing: 20) {
                // Animated loader
                ZStack {
                    // Track circle
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 3)
                        .frame(width: 52, height: 52)
                    
                    // Progress circle
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            Color.accentColor,
                            style: StrokeStyle(
                                lineWidth: 3,
                                lineCap: .round
                            )
                        )
                        .frame(width: 52, height: 52)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.3), value: progress)
                    
                    // Percentage text
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .opacity(showingIndeterminate ? 0 : 1)
                    
                    // Indeterminate spinner for initial load
                    Circle()
                        .trim(from: 0, to: 0.75)
                        .stroke(
                            Color.accentColor,
                            style: StrokeStyle(
                                lineWidth: 3,
                                lineCap: .round
                            )
                        )
                        .frame(width: 52, height: 52)
                        .rotationEffect(.degrees(rotation))
                        .opacity(showingIndeterminate ? 1 : 0)
                }
                
                Text("Processing Files")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.75))
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
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
