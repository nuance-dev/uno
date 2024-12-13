import SwiftUI

struct ModeSwitcher: View {
    @Binding var mode: ContentView.Mode
    @Namespace private var namespace
    
    var body: some View {
        ModeButtonContainer {
            ForEach(ContentView.Mode.allCases, id: \.self) { selectedMode in
                ModeButton(
                    mode: $mode,
                    selectedMode: selectedMode,
                    namespace: namespace
                )
            }
        }
    }
}

private struct ModeButtonContainer<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        HStack(spacing: 0) {
            content
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

private struct ModeButton: View {
    @Binding var mode: ContentView.Mode
    let selectedMode: ContentView.Mode
    var namespace: Namespace.ID
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                mode = selectedMode
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: selectedMode == .prompt ? "text.word.spacing" : "doc.fill")
                    .font(.system(size: 12))
                Text(selectedMode.rawValue)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(height: 28)
            .background(
                ZStack {
                    if mode == selectedMode {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.accentColor)
                            .matchedGeometryEffect(id: "ModeBackground", in: namespace)
                    }
                }
            )
            .foregroundColor(mode == selectedMode ? .white : .primary)
        }
        .buttonStyle(PlainButtonStyle())
    }
} 
