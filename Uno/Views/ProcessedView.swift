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
    @Environment(\.colorScheme) private var colorScheme
    
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
                                Color.accentColor.opacity(colorScheme == .dark ? 0.25 : 0.2) : 
                                Color.clear
                        )
                        .foregroundColor(selectedView == .files ? 
                            .accentColor : 
                            (colorScheme == .dark ? Color.secondary : Color.primary).opacity(0.7))
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
                                Color.accentColor.opacity(colorScheme == .dark ? 0.25 : 0.2) : 
                                Color.clear
                        )
                        .foregroundColor(selectedView == .processed ? 
                            .accentColor : 
                            (colorScheme == .dark ? Color.secondary : Color.primary).opacity(0.7))
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(colorScheme == .dark ? 0.15 : 0.1))
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
                                    .fill(isCopied ? 
                                        Color.green.opacity(colorScheme == .dark ? 0.15 : 0.1) : 
                                        Color.accentColor.opacity(colorScheme == .dark ? 0.15 : 0.1))
                                    .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else if mode == .pdf && selectedView == .processed {
                        Button(action: savePDF) {
                            Label("Save PDF", systemImage: "arrow.down.doc")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.accentColor)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.15 : 0.1))
                                        .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(processor.processedPDF == nil)
                    }
                    
                    Button(action: { showingClearConfirmation = true }) {
                        Label("Clear", systemImage: "trash")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor((colorScheme == .dark ? Color.secondary : Color.primary).opacity(0.7))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.secondary.opacity(colorScheme == .dark ? 0.15 : 0.1))
                                    .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
                            )
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
            .padding(.bottom, 12)
            
            // Main Content
            Group {
                if selectedView == .files {
                    fileListView
                } else {
                    if mode == .prompt {
                        promptResultView
                    } else {
                        pdfResultView
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.05))
            )
            
            if let error = processor.error {
                ErrorBanner(message: error)
                    .padding(.top, 12)
            }
        }
    }
    
    // File list view showing tree structure
    var fileListView: some View {
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
    var promptResultView: some View {
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
    var pdfResultView: some View {
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
                                .foregroundColor(.primary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Text("\(Int(zoomLevel * 100))%")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 40)
                        
                        Button(action: { zoomLevel = min(4.0, zoomLevel + 0.25) }) {
                            Image(systemName: "plus.magnifyingglass")
                                .font(.system(size: 12))
                                .foregroundColor(.primary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(colorScheme == .dark ? 0.15 : 0.08))
                    )
                }
            }
            .padding(16)
            
            Divider()
                .opacity(0.3)
            
            if let pdf = processor.processedPDF {
                EnhancedPDFKitView(pdfDocument: pdf, zoomLevel: CGFloat(zoomLevel))
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
            
            if let pdfDocument = self.processor.processedPDF {
                do {
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
                } catch {
                    DispatchQueue.main.async {
                        self.showError = true
                        self.errorMessage = "Failed to save PDF: \(error.localizedDescription)"
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.showError = true
                    self.errorMessage = "No PDF document available"
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
    @Environment(\.colorScheme) private var colorScheme
    
    var fileIcon: String {
        let ext = url.pathExtension.lowercased()
        
        switch ext {
        case "pdf": return "doc.fill"
        case "swift": return "swift"
        case "js": return "logo.javascript"
        case "ts": return "t.square" 
        case "html", "htm": return "chevron.left.forwardslash.chevron.right"
        case "css": return "paintbrush.fill"
        case "py": return "ladybug.fill"
        case "md", "markdown", "mdown": return "text.alignleft"
        case "txt": return "doc.text"
        case "json": return "curlybraces"
        case "yml", "yaml": return "list.bullet.indent"
        case "xml": return "chevron.left.square.fill.chevron.right"
        case "jpg", "jpeg", "png", "gif", "webp", "heic": return "photo.fill"
        case "mp3", "wav", "aac", "flac": return "music.note"
        case "mp4", "mov", "avi", "mkv": return "film.fill"
        case "zip", "rar", "7z", "tar", "gz": return "archivebox.fill"
        case "app", "exe": return "app.fill"
        case "sh", "bash", "zsh": return "terminal.fill"
        case "gitignore", "dockerignore": return "eye.slash.fill"
        default: return "doc"
        }
    }
    
    var fileColor: Color {
        let ext = url.pathExtension.lowercased()
        
        switch ext {
        case "pdf": return .red
        case "swift": return .orange
        case "js", "ts", "jsx", "tsx": return .yellow
        case "html", "htm", "xml": return .blue
        case "css", "scss", "less": return .purple
        case "py": return .green
        case "md", "markdown", "mdown", "txt": return .gray
        case "json", "yml", "yaml": return .teal
        case "jpg", "jpeg", "png", "gif", "webp", "heic": return .pink
        case "mp3", "wav", "aac", "flac", "mp4", "mov", "avi", "mkv": return .purple
        default: return .secondary
        }
    }
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: fileIcon)
                .font(.system(size: 14))
                .foregroundColor(fileColor)
                .frame(width: 20)
            
            Text(url.lastPathComponent)
                .font(.system(size: 14))
                .lineLimit(1)
            
            Spacer()
            
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 20, height: 20)
                    .background(
                        Circle()
                            .fill(Color.secondary.opacity(isHovering ? 0.15 : 0))
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .opacity(isHovering ? 1 : 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovering ? 
                    Color.secondary.opacity(colorScheme == .dark ? 0.1 : 0.08) : 
                    Color.clear)
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
    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if node.type == .directory {
                Button(action: { 
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 6) {
                        // Animated chevron that rotates when expanded/collapsed
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .animation(.spring(response: 0.2), value: isExpanded)
                        
                        // Folder icon that changes fill when expanded
                        Image(systemName: isExpanded ? "folder.fill" : "folder")
                            .font(.system(size: 14))
                            .foregroundColor(isExpanded ? .accentColor : .secondary)
                            .animation(.easeInOut(duration: 0.1), value: isExpanded)
                        
                        Text(node.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(isExpanded ? .primary : .secondary)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isHovering ? 
                                Color.secondary.opacity(colorScheme == .dark ? 0.1 : 0.08) : 
                                Color.clear)
                    )
                    .animation(.easeInOut(duration: 0.1), value: isHovering)
                }
                .buttonStyle(PlainButtonStyle())
                .onHover { hovering in
                    isHovering = hovering
                }
                
                if isExpanded && !node.children.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(node.children) { child in
                            FileTreeView(node: child)
                                .padding(.leading, 20)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: fileIconFor(filename: node.name))
                        .font(.system(size: 14))
                        .foregroundColor(fileColorFor(filename: node.name))
                    
                    Text(node.name)
                        .font(.system(size: 14))
                        .lineLimit(1)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isHovering ? 
                            Color.secondary.opacity(colorScheme == .dark ? 0.1 : 0.08) : 
                            Color.clear)
                )
                .onHover { hovering in
                    isHovering = hovering
                }
                .animation(.easeInOut(duration: 0.1), value: isHovering)
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
        case "html", "htm": return "chevron.left.forwardslash.chevron.right"
        case "css": return "paintbrush.fill"
        case "py": return "ladybug.fill"
        case "md", "markdown", "mdown": return "text.alignleft"
        case "txt": return "doc.text"
        case "json": return "curlybraces"
        case "yml", "yaml": return "list.bullet.indent"
        case "xml": return "chevron.left.square.fill.chevron.right"
        case "jpg", "jpeg", "png", "gif", "webp", "heic": return "photo.fill"
        case "mp3", "wav", "aac", "flac": return "music.note"
        case "mp4", "mov", "avi", "mkv": return "film.fill"
        case "zip", "rar", "7z", "tar", "gz": return "archivebox.fill"
        case "app", "exe": return "app.fill"
        case "sh", "bash", "zsh": return "terminal.fill"
        case "gitignore", "dockerignore": return "eye.slash.fill"
        default: return "doc"
        }
    }
    
    private func fileColorFor(filename: String) -> Color {
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        
        switch ext {
        case "pdf": return .red
        case "swift": return .orange
        case "js", "ts", "jsx", "tsx": return .yellow
        case "html", "htm", "xml": return .blue
        case "css", "scss", "less": return .purple
        case "py": return .green
        case "md", "markdown", "mdown", "txt": return .gray
        case "json", "yml", "yaml": return .teal
        case "jpg", "jpeg", "png", "gif", "webp", "heic": return .pink
        case "mp3", "wav", "aac", "flac", "mp4", "mov", "avi", "mkv": return .purple
        default: return .secondary
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
    
    func makeNSView(context: Context) -> NSView {
        // Create container for PDF view and controls
        let container = NSView()
        
        // Create PDF view
        let pdfView = PDFKit.PDFView()
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        configurePDFView(pdfView)
        
        // Create controls container
        let controlsContainer = NSVisualEffectView()
        controlsContainer.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.material = .menu
        controlsContainer.blendingMode = .behindWindow
        controlsContainer.state = .active
        controlsContainer.wantsLayer = true
        controlsContainer.layer?.cornerRadius = 8
        
        // Create page navigation controls
        let controlsStack = NSStackView()
        controlsStack.translatesAutoresizingMaskIntoConstraints = false
        controlsStack.orientation = .horizontal
        controlsStack.spacing = 16
        controlsStack.alignment = .centerY
        controlsStack.distribution = .gravityAreas
        
        // First page button
        let firstButton = NSButton(image: NSImage(systemSymbolName: "chevron.left.to.line", accessibilityDescription: "First Page")!, target: context.coordinator, action: #selector(Coordinator.goToFirstPage(_:)))
        firstButton.isBordered = false
        firstButton.bezelStyle = .roundRect
        
        // Previous page button
        let prevButton = NSButton(image: NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Previous Page")!, target: context.coordinator, action: #selector(Coordinator.goToPreviousPage(_:)))
        prevButton.isBordered = false
        prevButton.bezelStyle = .roundRect
        
        // Page label
        let pageLabel = NSTextField(labelWithString: "Page 1 of \(pdfDocument.pageCount)")
        pageLabel.translatesAutoresizingMaskIntoConstraints = false
        pageLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        pageLabel.alignment = .center
        pageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.pageLabel = pageLabel
        
        // Next page button
        let nextButton = NSButton(image: NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Next Page")!, target: context.coordinator, action: #selector(Coordinator.goToNextPage(_:)))
        nextButton.isBordered = false
        nextButton.bezelStyle = .roundRect
        
        // Last page button
        let lastButton = NSButton(image: NSImage(systemSymbolName: "chevron.right.to.line", accessibilityDescription: "Last Page")!, target: context.coordinator, action: #selector(Coordinator.goToLastPage(_:)))
        lastButton.isBordered = false
        lastButton.bezelStyle = .roundRect
        
        // Add buttons to stack
        controlsStack.addArrangedSubview(firstButton)
        controlsStack.addArrangedSubview(prevButton)
        controlsStack.addArrangedSubview(pageLabel)
        controlsStack.addArrangedSubview(nextButton)
        controlsStack.addArrangedSubview(lastButton)
        
        // Add controls to container
        controlsContainer.addSubview(controlsStack)
        
        // Add views to container
        container.addSubview(pdfView)
        container.addSubview(controlsContainer)
        
        // Store references for the coordinator
        context.coordinator.pdfView = pdfView
        
        // Set constraints
        NSLayoutConstraint.activate([
            // PDF view fills the container
            pdfView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            pdfView.topAnchor.constraint(equalTo: container.topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            
            // Controls container centered at bottom
            controlsContainer.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            controlsContainer.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
            
            // Control stack within container
            controlsStack.leadingAnchor.constraint(equalTo: controlsContainer.leadingAnchor, constant: 12),
            controlsStack.trailingAnchor.constraint(equalTo: controlsContainer.trailingAnchor, constant: -12),
            controlsStack.topAnchor.constraint(equalTo: controlsContainer.topAnchor, constant: 8),
            controlsStack.bottomAnchor.constraint(equalTo: controlsContainer.bottomAnchor, constant: -8),
            
            // Fixed width for page label
            pageLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 120)
        ])
        
        return container
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let pdfView = context.coordinator.pdfView else { return }
        
        // Update the PDF document and scale
        pdfView.document = pdfDocument
        pdfView.scaleFactor = zoomLevel
        pdfView.needsLayout = true
        pdfView.layoutDocumentView()
        
        // Update page label
        if let pageLabel = context.coordinator.pageLabel, 
           let currentPage = pdfView.currentPage {
            // Use pageIndex directly since it's already a non-optional Int
            let pageIndex = pdfDocument.index(for: currentPage)
            pageLabel.stringValue = "Page \(pageIndex + 1) of \(pdfDocument.pageCount)"
        }
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
        
        // Configure for better user experience
        pdfView.acceptsDraggedFiles = false
        pdfView.enableDataDetectors = false
        
        // Set initial zoom to fit width
        DispatchQueue.main.async {
            if let firstPage = pdfDocument.page(at: 0) {
                let pageSize = firstPage.bounds(for: .mediaBox)
                let viewWidth = pdfView.bounds.width - 40 // Account for insets
                pdfView.scaleFactor = viewWidth / pageSize.width
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(pdfDocument)
    }
    
    class Coordinator: NSObject, PDFViewDelegate {
        let pdfDocument: PDFKit.PDFDocument
        var pdfView: PDFKit.PDFView?
        var pageLabel: NSTextField?
        
        init(_ pdfDocument: PDFKit.PDFDocument) {
            self.pdfDocument = pdfDocument
            super.init()
        }
        
        @objc func goToFirstPage(_ sender: NSButton) {
            guard let pdfView = pdfView, let firstPage = pdfDocument.page(at: 0) else { return }
            pdfView.go(to: firstPage)
            updatePageLabel()
        }
        
        @objc func goToPreviousPage(_ sender: NSButton) {
            guard let pdfView = pdfView else { return }
            pdfView.goToPreviousPage(sender)
            updatePageLabel()
        }
        
        @objc func goToNextPage(_ sender: NSButton) {
            guard let pdfView = pdfView else { return }
            pdfView.goToNextPage(sender)
            updatePageLabel()
        }
        
        @objc func goToLastPage(_ sender: NSButton) {
            guard let pdfView = pdfView else { return }
            
            // Fix: Use pageCount safely with bounds check
            let lastPageIndex = max(0, pdfDocument.pageCount - 1)
            if let lastPage = pdfDocument.page(at: lastPageIndex) {
                pdfView.go(to: lastPage)
            }
            updatePageLabel()
        }
        
        private func updatePageLabel() {
            guard let pdfView = pdfView, 
                  let pageLabel = pageLabel,
                  let currentPage = pdfView.currentPage else { return }
            
            // Use pageIndex directly since it's already a non-optional Int
            let pageIndex = pdfDocument.index(for: currentPage)
            pageLabel.stringValue = "Page \(pageIndex + 1) of \(pdfDocument.pageCount)"
        }
    }
} 
