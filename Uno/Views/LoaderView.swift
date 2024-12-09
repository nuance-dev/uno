import SwiftUI

struct LoaderView: View {
    @State private var isAnimating = false
    let progress: Double
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
                
                // Progress ring
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 54, height: 54)
                    .rotationEffect(.degrees(-90))
                
                // Percentage text
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .offset(y: 46)
            }
        }
    }
}

#Preview {
    LoaderView(progress: 0.5)
        .frame(width: 400, height: 400)
}
