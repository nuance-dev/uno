import SwiftUI

struct LoaderView: View {
    let progress: Double
    
    var body: some View {
        ProcessingOverlay(progress: progress, filesCount: 0)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.3), value: progress)
    }
}

#Preview {
    LoaderView(progress: 0.5)
        .frame(width: 400, height: 400)
}
