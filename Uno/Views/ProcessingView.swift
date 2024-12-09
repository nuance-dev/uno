import SwiftUI
import PDFKit
import os

private let logger = Logger(subsystem: "me.nuanc.Uno", category: "ProcessingView")

struct ProcessingView: View {
    @ObservedObject var processor: FileProcessor
    let mode: ContentView.Mode
    @State private var isCopied = false
    @State private var showingClearConfirmation = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var zoomLevel: Double = 1.0
    
    var clearButton: some View {
        Button(action: {
            showingClearConfirmation = true
        }) {
            HStack(spacing: 6) {
                Image(systemName: "trash")
                Text("Clear All")
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.red.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.red.opacity(0.2), lineWidth: 1)
            )
            .foregroundColor(.red)
        }
        .buttonStyle(PlainButtonStyle())
        .help("Clear all files")
        .confirmationDialog(
            "Clear All Files",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                withAnimation(.spring(response: 0.3)) {
                    processor.clearFiles()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to clear all files? This action cannot be undone.")
        }
    }
    
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
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
                
                if !processor.files.isEmpty {
                    clearButton
                }
            }
            .frame(height: 40)
            
            // Result View
            if mode == .prompt {
                PromptView(content: processor.processedContent, isCopied: $isCopied)
            } else {
                PDFPreviewView(processor: processor, pdfDocument: processor.processedPDF)
            }
            
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
        pdfView.displayMode = .singlePageContinuous
        pdfView.backgroundColor = .clear
        pdfView.displaysPageBreaks = true
        pdfView.displayDirection = .vertical
        
        // Improve default sizing
        pdfView.scaleFactor = pdfView.scaleFactorForSizeToFit
        pdfView.maxScaleFactor = 4.0
        pdfView.minScaleFactor = 0.25
        
        // Enable smooth scrolling
        if let scrollView = pdfView.documentView?.enclosingScrollView {
            scrollView.hasVerticalScroller = true
            scrollView.scrollerStyle = .overlay
            
            // Set content insets for better presentation
            scrollView.contentInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        }
        
        return pdfView
    }
    
    func updateNSView(_ pdfView: PDFKit.PDFView, context: Context) {
        pdfView.document = pdfDocument
        pdfView.scaleFactor = pdfView.scaleFactorForSizeToFit
        pdfView.needsLayout = true
        pdfView.layoutDocumentView()
    }
}

struct PDFPreviewView: View {
    @ObservedObject var processor: FileProcessor
    let pdfDocument: PDFKit.PDFDocument?
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var zoomLevel: CGFloat = 1.0
    @State private var isSaving: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("PDF Preview")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if pdfDocument != nil {
                    HStack(spacing: 12) {
                        // Zoom controls
                        HStack(spacing: 8) {
                            Button(action: { zoomLevel = max(0.25, zoomLevel - 0.25) }) {
                                Image(systemName: "minus.magnifyingglass")
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Text("\(Int(zoomLevel * 100))%")
                                .font(.system(size: 11, weight: .medium))
                                .frame(width: 40)
                            
                            Button(action: { zoomLevel = min(4.0, zoomLevel + 0.25) }) {
                                Image(systemName: "plus.magnifyingglass")
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(NSColor.controlBackgroundColor))
                        )
                        
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
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Divider()
                .opacity(0.5)
            
            if let pdf = pdfDocument {
                EnhancedPDFKitView(pdfDocument: pdf, zoomLevel: zoomLevel)
            } else {
                EmptyStateView()
            }
        }
        .alert("Error Saving PDF", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func savePDF() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf]
        savePanel.nameFieldStringValue = "Merged.pdf"
        
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            
            do {
                if let pdfDocument = self.pdfDocument {
                    try pdfDocument.write(to: url)
                    
                    // Show success feedback
                    DispatchQueue.main.async {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                        
                        // Optional: Show success notification
                        let notification = NSUserNotification()
                        notification.title = "PDF Saved"
                        notification.informativeText = "Your PDF has been saved successfully"
                        NSUserNotificationCenter.default.deliver(notification)
                    }
                } else {
                    throw NSError(
                        domain: "PDFError",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "No PDF document available"]
                    )
                }
            } catch {
                DispatchQueue.main.async {
                    self.showError = true
                    self.errorMessage = "Failed to save PDF: \(error.localizedDescription)"
                }
            }
        }
    }
}

struct EnhancedPDFKitView: NSViewRepresentable {
    let pdfDocument: PDFKit.PDFDocument
    let zoomLevel: CGFloat
    
    func makeNSView(context: Context) -> PDFKit.PDFView {
        let pdfView = PDFKit.PDFView()
        configurePDFView(pdfView)
        return pdfView
    }
    
    func updateNSView(_ pdfView: PDFKit.PDFView, context: Context) {
        pdfView.document = pdfDocument
        pdfView.scaleFactor = zoomLevel
        pdfView.needsLayout = true
        pdfView.layoutDocumentView()
    }
    
    private func configurePDFView(_ pdfView: PDFKit.PDFView) {
        pdfView.document = pdfDocument
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.backgroundColor = .clear
        pdfView.displaysPageBreaks = true
        pdfView.displayDirection = .vertical
        pdfView.maxScaleFactor = 4.0
        pdfView.minScaleFactor = 0.25
        
        // Enable smooth scrolling
        if let scrollView = pdfView.documentView?.enclosingScrollView {
            scrollView.hasVerticalScroller = true
            scrollView.scrollerStyle = .overlay
            scrollView.contentInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        }
        
        // Set initial zoom to fit width
        DispatchQueue.main.async {
            if let firstPage = pdfDocument.page(at: 0) {
                let pageSize = firstPage.bounds(for: .mediaBox)
                let viewWidth = pdfView.bounds.width - 40 // Account for insets
                let scale = viewWidth / pageSize.width
                pdfView.scaleFactor = scale
            }
        }
    }
} 
