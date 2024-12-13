import SwiftUI

struct ProcessingOverlay: View {
    let progress: Double
    let filesCount: Int
    @State private var showingDetail = false
    @State private var rotation = 0.0
    
    var body: some View {
        VStack(spacing: 24) {
            // Animated progress ring
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.1), lineWidth: 8)
                    .frame(width: 80, height: 80)
                
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        LinearGradient(
                            colors: [.accentColor, .accentColor.opacity(0.6)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                
                VStack(spacing: 2) {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 18, weight: .medium))
                    if filesCount > 0 {
                        Text("\(filesCount) files")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            VStack(spacing: 8) {
                Text("Processing Files")
                    .font(.headline)
                
                Text("This might take a moment...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            if showingDetail {
                Text("Optimizing and analyzing content...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .frame(width: 240)
        .padding(32)
        .background(
            ZStack {
                VisualEffectBlur(material: .popover, blendingMode: .behindWindow)
                
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.primary.opacity(0.05))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.1), radius: 20, y: 10)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).delay(0.5)) {
                showingDetail = true
            }
        }
    }
} 