import SwiftUI
import PDFKit
import os
import UserNotifications

private let logger = Logger(subsystem: "me.nuanc.Uno", category: "ProcessedView")

struct ProcessedView: View {
    @ObservedObject var processor: FileProcessor
    let mode: ContentView.Mode
    @State private var isCopied = false
    @State private var showingClearConfirmation = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var zoomLevel: Double = 1.0
    @State private var selectedView: ViewMode = .processed
    
    enum ViewMode {
        case files, processed
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Top toolbar
            HStack(spacing: 16) {
                // View mode selector
                HStack(spacing: 0) {
                    Button(action: { selectedView = .files }) {
                        HStack(spacing: 6) {
                            Image(systemName: "folder")
                                .font(.system(size: 12))
                            Text("Files")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            selectedView == .files ? 
                                Color.accentColor.opacity(0.2) : 
                                Color.clear
                        )
                        .foregroundColor(selectedView == .files ? .accentColor : .secondary)
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: { selectedView = .processed }) {
                        HStack(spacing: 6) {
                            Image(systemName: mode == .prompt ? "doc.text" : "doc.richtext")
                                .font(.system(size: 12))
                            Text(mode == .prompt ? "Prompt" : "PDF")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            selectedView == .processed ? 
                                Color.accentColor.opacity(0.2) : 
                                Color.clear
                        )
                        .foregroundColor(selectedView == .processed ? .accentColor : .secondary)
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.1))
                )
                
                Spacer()
                
                if !processor.files.isEmpty {
                    // Action buttons
                    if mode == .prompt && selectedView == .processed {
                        Button(action: copyToClipboard) {
                            Label(
                                isCopied ? "Copied" : "Copy",
                                systemImage: isCopied ? "checkmark" : "doc.on.clipboard"
                            )
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(isCopied ? .green : .accentColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.accentColor.opacity(0.1))
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .transition(.opacity)
                    } else if mode == .pdf && selectedView == .processed {
                        Button(action: savePDF) {
                            Label("Save PDF", systemImage: "arrow.down.doc")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.accentColor)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.accentColor.opacity(0.1))
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .transition(.opacity)
                    }
                    
                    // Clear button
                    Button(action: { showingClearConfirmation = true }) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .confirmationDialog(
                        "Clear all files?",
                        isPresented: $showingClearConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Clear", role: .destructive) {
                            processor.clearFiles()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will remove all loaded files.")
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 10)
            
            // Main content area
            Group {
                if selectedView == .files {
                    fileList
                } else {
                    if mode == .prompt {
                        promptView
                    } else {
                        pdfView
                    }
                }
            }
        }
        .animation(.spring(response: 0.3), value: selectedView)
        .alert(isPresented: $showError) {
            Alert(
                title: Text("Error"),
                message: Text(errorMessage),
                dismissButton: .default(Text("OK"))
            )
        }
    }
    
    // File list view showing tree structure
    var fileList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Files")
                .font(.headline)
                .padding(16)
            
            Divider()
                .opacity(0.3)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let fileTree = processor.fileTree {
                        FileTreeView(node: fileTree)
                    } else {
                        // Flat file list as fallback
                        ForEach(processor.files, id: \.self) { url in
                            FileItemView(url: url) {
                                withAnimation {
                                    if let index = processor.files.firstIndex(of: url) {
                                        processor.files.remove(at: index)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
    }
    
    // Prompt result view
    var promptView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Prompt Output")
                .font(.headline)
                .padding(16)
            
            Divider()
                .opacity(0.3)
            
            if processor.processedContent.isEmpty {
                EmptyStateView()
            } else if let attributedContent = processor.processedAttributedContent, processor.useSyntaxHighlighting {
                // Use attributed text with syntax highlighting
                AttributedTextView(attributedString: attributedContent)
            } else {
                // Use plain text
                ScrollView {
                    Text(processor.processedContent)
                        .font(.system(.body, design: .monospaced))
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        }
    }
    
    // PDF result view
    var pdfView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("PDF Preview")
                    .font(.headline)
                
                Spacer()
                
                if processor.processedPDF != nil {
                    HStack(spacing: 8) {
                        Button(action: { zoomLevel = max(0.25, zoomLevel - 0.25) }) {
                            Image(systemName: "minus.magnifyingglass")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Text("\(Int(zoomLevel * 100))%")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 40)
                        
                        Button(action: { zoomLevel = min(4.0, zoomLevel + 0.25) }) {
                            Image(systemName: "plus.magnifyingglass")
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
            .padding(16)
            
            Divider()
                .opacity(0.3)
            
            if let pdf = processor.processedPDF {
                EnhancedPDFKitView(pdfDocument: pdf, zoomLevel: zoomLevel)
            } else {
                EmptyStateView()
            }
        }
    }
    
    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(processor.processedContent, forType: .string)
        
        withAnimation {
            isCopied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                isCopied = false
            }
        }
    }
    
    private func savePDF() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf]
        savePanel.nameFieldStringValue = "Merged.pdf"
        
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            
            do {
                if let pdfDocument = self.processor.processedPDF {
                    try pdfDocument.write(to: url)
                    
                    // Show success feedback
                    DispatchQueue.main.async {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                        
                        // Replace deprecated NSUserNotification with UNUserNotificationCenter
                        let content = UNMutableNotificationContent()
                        content.title = "PDF Saved"
                        content.body = "Your PDF has been saved successfully"
                        
                        let request = UNNotificationRequest(
                            identifier: UUID().uuidString,
                            content: content,
                            trigger: nil
                        )
                        
                        UNUserNotificationCenter.current().add(request) { error in
                            if let error = error {
                                logger.error("Notification error: \(error.localizedDescription)")
                            }
                        }
                    }
                } else {
                    let error = NSError(
                        domain: "PDFError",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "No PDF document available"]
                    )
                    throw error
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

// NSTextView wrapper for displaying attributed text with syntax highlighting
struct AttributedTextView: NSViewRepresentable {
    var attributedString: NSAttributedString
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        
        if let textView = scrollView.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.textContainerInset = NSSize(width: 16, height: 16)
            textView.textContainer?.widthTracksTextView = true
            textView.textContainer?.heightTracksTextView = false
            textView.backgroundColor = .clear
            
            // Setup text view
            textView.textStorage?.setAttributedString(attributedString)
            textView.layoutManager?.allowsNonContiguousLayout = true
            textView.layoutManager?.defaultAttachmentScaling = .scaleProportionallyDown
        }
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let textView = nsView.documentView as? NSTextView {
            textView.textStorage?.setAttributedString(attributedString)
        }
    }
}

// File item view for showing individual files
struct FileItemView: View {
    let url: URL
    let onRemove: () -> Void
    @State private var isHovering = false
    
    var fileIcon: String {
        switch url.pathExtension.lowercased() {
        case "pdf": return "doc.fill"
        case "swift": return "swift"
        case "js": return "logo.javascript"
        case "ts": return "t.square"
        case "html": return "chevron.left.forwardslash.chevron.right"
        case "css": return "paintbrush.fill"
        case "py": return "ladybug.fill"
        case "md", "txt": return "doc.text"
        case "json": return "curlybraces"
        case "jpg", "jpeg", "png", "gif", "webp": return "photo"
        default: return "doc.text"
        }
    }
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: fileIcon)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 20)
            
            Text(url.lastPathComponent)
                .font(.system(size: 14))
                .lineLimit(1)
            
            Spacer()
            
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .opacity(isHovering ? 1 : 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovering ? Color.secondary.opacity(0.1) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
}

// File tree view for showing hierarchical file structure
struct FileTreeView: View {
    let node: FileNode
    @State private var isExpanded = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if node.type == .directory {
                Button(action: { isExpanded.toggle() }) {
                    HStack(spacing: 6) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        
                        Image(systemName: "folder\(isExpanded ? ".fill" : "")")
                            .font(.system(size: 14))
                            .foregroundColor(isExpanded ? .accentColor : .secondary)
                        
                        Text(node.name)
                            .font(.system(size: 14, weight: .medium))
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                if isExpanded && !node.children.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(node.children) { child in
                            FileTreeView(node: child)
                                .padding(.leading, 20)
                        }
                    }
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: fileIconFor(filename: node.name))
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    
                    Text(node.name)
                        .font(.system(size: 14))
                        .lineLimit(1)
                }
                .padding(.vertical, 4)
            }
        }
    }
    
    private func fileIconFor(filename: String) -> String {
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        
        switch ext {
        case "pdf": return "doc.fill"
        case "swift": return "swift"
        case "js": return "logo.javascript"
        case "ts": return "t.square"
        case "html": return "chevron.left.forwardslash.chevron.right"
        case "css": return "paintbrush.fill"
        case "py": return "ladybug.fill"
        case "md", "txt": return "doc.text"
        case "json": return "curlybraces"
        case "jpg", "jpeg", "png", "gif", "webp": return "photo"
        default: return "doc.text"
        }
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("No content to display")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
            
            Text("Add files to generate output")
                .font(.system(size: 14))
                .foregroundColor(.secondary.opacity(0.8))
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
                .font(.system(size: 13))
            
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.opacity(0.1))
        )
    }
}

// PDFKit wrapper with enhanced UI
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
