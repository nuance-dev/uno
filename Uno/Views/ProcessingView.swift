import SwiftUI
import PDFKit

struct ProcessingView: View {
    @ObservedObject var processor: FileProcessor
    let mode: ContentView.Mode
    @State private var isCopied = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Files List with improved design
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(processor.files, id: \.self) { url in
                        FileTag(url: url) {
                            withAnimation(.spring(response: 0.3)) {
                                if let index = processor.files.firstIndex(of: url) {
                                    processor.files.remove(at: index)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            .frame(height: 32)
            
            // Result View
            if mode == .prompt {
                PromptView(content: processor.processedContent, isCopied: $isCopied)
            } else {
                PDFPreviewView(pdfDocument: processor.processedPDF)
            }
            
            // Error Display
            if let error = processor.error {
                ErrorBanner(message: error)
            }
        }
    }
}

struct FileTag: View {
    let url: URL
    let onRemove: () -> Void
    
    private var fileIcon: String {
        switch url.pathExtension.lowercased() {
        case "pdf": return "doc.fill"
        case "swift": return "swift"
        case "js": return "logo.javascript"
        case "ts": return "t.square"
        case "html": return "chevron.left.forwardslash.chevron.right"
        case "css": return "paintbrush.fill"
        default: return "doc.text"
        }
    }
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: fileIcon)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            Text(url.lastPathComponent)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.8))
            }
            .buttonStyle(PlainButtonStyle())
            .opacity(0.6)
            .contentShape(Rectangle())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.8))
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            }
        )
        .transition(.scale.combined(with: .opacity))
    }
}

struct PromptView: View {
    let content: String
    @Binding var isCopied: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Output")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if !content.isEmpty {
                    Button(action: copyToClipboard) {
                        HStack(spacing: 4) {
                            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 11))
                            Text(isCopied ? "Copied" : "Copy")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.accentColor.opacity(0.1))
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Divider()
                .opacity(0.5)
            
            if content.isEmpty {
                EmptyStateView()
            } else {
                ScrollView {
                    Text(content)
                        .font(.system(.body, design: .monospaced))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                )
        )
    }
    
    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        
        withAnimation {
            isCopied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                isCopied = false
            }
        }
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.5))
            Text("Add files to generate output")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct ErrorBanner: View {
    let message: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(message)
                .font(.system(size: 12))
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.red.opacity(0.1))
        )
        .padding(.horizontal)
    }
}

// PDFKit wrapper
struct PDFKitView: NSViewRepresentable {
    let pdfDocument: PDFKit.PDFDocument
    
    func makeNSView(context: Context) -> PDFKit.PDFView {
        let pdfView = PDFKit.PDFView()
        pdfView.document = pdfDocument
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.backgroundColor = .clear
        return pdfView
    }
    
    func updateNSView(_ pdfView: PDFKit.PDFView, context: Context) {
        pdfView.document = pdfDocument
    }
}

struct PDFPreviewView: View {
    let pdfDocument: PDFKit.PDFDocument?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("PDF Preview")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if pdfDocument != nil {
                    Button(action: savePDF) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 11))
                            Text("Save")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.accentColor.opacity(0.1))
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Divider()
                .opacity(0.5)
            
            if let pdf = pdfDocument {
                PDFKitView(pdfDocument: pdf)
            } else {
                EmptyStateView()
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                )
        )
    }
    
    private func savePDF() {
        guard let pdf = pdfDocument else { return }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf]
        savePanel.nameFieldStringValue = "Merged.pdf"
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                try? pdf.write(to: url)
            }
        }
    }
} 