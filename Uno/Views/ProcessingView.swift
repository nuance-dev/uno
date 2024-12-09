import SwiftUI
import PDFKit

struct ProcessingView: View {
    @ObservedObject var processor: FileProcessor
    let mode: ContentView.Mode
    
    var body: some View {
        VStack(spacing: 16) {
            // Files List
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(processor.files, id: \.self) { url in
                        FileItemView(url: url) {
                            if let index = processor.files.firstIndex(of: url) {
                                processor.files.remove(at: index)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            .frame(height: 40)
            
            // Result View
            if mode == .prompt {
                PromptResultView(content: processor.processedContent)
            } else {
                PDFResultView(document: processor.processedPDF)
            }
            
            // Error Display
            if let error = processor.error {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            // Action Buttons
            HStack(spacing: 12) {
                Button(action: {
                    processor.clearFiles()
                }) {
                    Label("Clear", systemImage: "xmark")
                }
                .buttonStyle(GlassButtonStyle())
                
                Button(action: {
                    processor.processFiles(mode: mode)
                }) {
                    Label(mode == .prompt ? "Generate Prompt" : "Create PDF", 
                          systemImage: mode == .prompt ? "text.word.spacing" : "doc.fill")
                }
                .buttonStyle(GlassButtonStyle())
                
                if !processor.processedContent.isEmpty || processor.processedPDF != nil {
                    Button(action: {
                        saveResult()
                    }) {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(GlassButtonStyle())
                }
            }
        }
    }
    
    private func saveResult() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [mode == .prompt ? .plainText : .pdf]
        savePanel.nameFieldStringValue = mode == .prompt ? "prompt.txt" : "merged.pdf"
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    if mode == .prompt {
                        try processor.processedContent.write(to: url, atomically: true, encoding: .utf8)
                    } else if let pdfData = processor.processedPDF?.dataRepresentation() {
                        try pdfData.write(to: url)
                    }
                } catch {
                    processor.error = "Error saving file: \(error.localizedDescription)"
                }
            }
        }
    }
}

// Helper Views
struct FileItemView: View {
    let url: URL
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "doc")
                .font(.system(size: 12))
            Text(url.lastPathComponent)
                .font(.system(size: 12))
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.1))
        )
    }
}

struct PromptResultView: View {
    let content: String
    
    var body: some View {
        ScrollView {
            Text(content)
                .font(.system(.body, design: .monospaced))
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.1))
        )
    }
}

struct PDFResultView: View {
    let document: PDFDocument?
    
    var body: some View {
        if let document = document {
            PDFKitView(document: document)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            Color.clear
        }
    }
}

// PDFKit wrapper
struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument
    
    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        return pdfView
    }
    
    func updateNSView(_ nsView: PDFView, context: Context) {
        nsView.document = document
    }
} 