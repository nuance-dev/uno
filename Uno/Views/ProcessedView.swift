import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import os
import UserNotifications

private let logger = Logger(subsystem: "me.nuanc.Uno", category: "ProcessedView")

struct ProcessedView: View {
    @ObservedObject var processor: FileProcessor
    let mode: ContentView.Mode
    @State private var isCopied = false
    @State private var showingClearConfirmation = false
    @State private var zoomLevel: Double = 1.0
    @State private var draggedItem: URL?
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        VStack(spacing: 10) {
            // Files header with reordering
            HStack(spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 6) {
                        ForEach(processor.files, id: \.self) { url in
                            FileTag(url: url, onRemove: {
                                withAnimation(.spring(response: 0.3)) {
                                    processor.removeFile(url)
                                }
                            })
                            .opacity(draggedItem == url ? 0.5 : 1.0)
                            .onDrag {
                                draggedItem = url
                                return NSItemProvider(object: url as NSURL)
                            }
                            .onDrop(of: [.fileURL], delegate: FileDropDelegate(item: url, items: processor.files, draggedItem: $draggedItem) { from, to in
                                withAnimation(.spring(response: 0.3)) {
                                    processor.moveFile(from: from, to: to)
                                }
                            })
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
                
                if !processor.files.isEmpty {
                    Button(action: { showingClearConfirmation = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                            Text("Clear")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                        .foregroundColor(.red)
                    }
                    .buttonStyle(PlainButtonStyle())
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
            }
            .frame(height: 36)
            
            // Content area
            if mode == .prompt {
                PromptView(content: processor.processedContent, isCopied: $isCopied) {
                    HStack {
                        Spacer()
                        Text("\(TokenCounter.formatTokenCount(TokenCounter.estimateTokenCount(processor.processedContent))) tokens")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.secondary.opacity(0.1))
                            )
                    }
                    .padding(.trailing, 12)
                    .padding(.bottom, 8)
                }
            } else {
                PDFPreviewView(processor: processor, pdfDocument: processor.processedPDF)
            }
            
            if let error = processor.error {
                ErrorBanner(message: error)
            }
        }
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
    private let memoryManager = MemoryManager.shared
    
    func makeNSView(context: Context) -> PDFKit.PDFView {
        let pdfView = PDFKit.PDFView()
        memoryManager.beginMemoryIntensiveTask()
        
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
        autoreleasepool {
            pdfView.document = pdfDocument
            pdfView.scaleFactor = pdfView.scaleFactorForSizeToFit
            pdfView.needsLayout = true
            pdfView.layoutDocumentView()
            
            memoryManager.cleanupIfNeeded()
        }
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
                    
                    // Show success feedback using modern UserNotifications
                    DispatchQueue.main.async {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                        
                        let content = UNMutableNotificationContent()
                        content.title = "PDF Saved"
                        content.body = "Your PDF has been saved successfully"
                        
                        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                                          content: content,
                                                          trigger: nil)
                        
                        UNUserNotificationCenter.current().add(request) { error in
                            if let error = error {
                                print("Error showing notification: \(error.localizedDescription)")
                            }
                        }
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

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No preview available")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
