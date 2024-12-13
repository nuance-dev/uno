import SwiftUI

struct PromptView<Footer: View>: View {
    let content: String
    @Binding var isCopied: Bool
    let footer: Footer
    
    init(content: String, isCopied: Binding<Bool>, @ViewBuilder footer: () -> Footer) {
        self.content = content
        self._isCopied = isCopied
        self.footer = footer()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    TextEditor(text: .constant(content))
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                    
                    footer
                }
            }
            .background(Color(NSColor.textBackgroundColor))
            
            Divider()
            
            HStack {
                Spacer()
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(content, forType: .string)
                    withAnimation {
                        isCopied = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            isCopied = false
                        }
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        Text(isCopied ? "Copied!" : "Copy")
                    }
                    .frame(width: 100)
                }
                .buttonStyle(.borderedProminent)
                .disabled(content.isEmpty)
            }
            .padding(12)
            .background(VisualEffectBlur(material: .contentBackground, blendingMode: .behindWindow))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
} 