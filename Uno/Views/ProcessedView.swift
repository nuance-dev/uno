import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import os
import UserNotifications

private let logger = Logger(subsystem: "me.nuanc.Uno", category: "ProcessedView")

struct ProcessedView: View {
    @ObservedObject var processor: FileProcessor
    let mode: ContentView.Mode
    @State private var showTreeView = false
    @State private var treeStructure: FolderNode?
    @State private var selectedNode: FolderNode?
    @State private var isCopied = false
    @State private var hoveredFile: URL?
    @State private var draggedItem: URL?
    @State private var showClearConfirmation = false
    
    var body: some View {
        HStack(spacing: 0) {
            if showTreeView {
                TreeSidebarView(structure: treeStructure)
                    .frame(width: 240)
                    .transition(.move(edge: .leading))
            }
            
            VStack(spacing: 0) {
                FileHeaderView(
                    processor: processor,
                    hoveredFile: $hoveredFile,
                    draggedItem: $draggedItem,
                    showClearConfirmation: $showClearConfirmation
                )
                
                Divider()
                
                // Main content area
                if mode == .prompt {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if processor.includeTreeInPrompt {
                                Text("File Structure")
                                    .font(.headline)
                                    .padding(.top)
                            }
                            Text(processor.processedContent)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .padding()
                        }
                    }
                } else {
                    PDFPreviewView(processor: processor, 
                                 pdfDocument: processor.processedPDF)
                }
            }
        }
        .alert("Clear All Files?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                withAnimation(.spring(response: 0.3)) {
                    processor.clearFiles()
                }
            }
        } message: {
            Text("This will remove all files from the current session.")
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                toolbarItems
            }
        }
        .onAppear {
            updateTreeStructure()
        }
        .onChange(of: processor.files) { oldValue, newValue in
            updateTreeStructure()
        }
    }
    
    private func updateTreeStructure() {
        guard let firstFile = processor.files.first else {
            treeStructure = nil
            return
        }
        
        do {
            let rootURL = firstFile.deletingLastPathComponent()
            treeStructure = try processor.buildFolderStructure(rootURL)
        } catch {
            logger.error("Failed to build folder structure: \(error.localizedDescription)")
            treeStructure = nil
        }
    }
    
    private var toolbarItems: some View {
        HStack(spacing: 16) {
            if mode == .prompt {
                Toggle(isOn: $processor.includeTreeInPrompt) {
                    Label("Include Tree", systemImage: "list.bullet.indent")
                }
                .toggleStyle(.button)
                .controlSize(.small)
            }
            
            Button(action: { showTreeView.toggle() }) {
                Label("File Tree", systemImage: "sidebar.left")
            }
            .buttonStyle(.plain)
            .foregroundColor(showTreeView ? .accentColor : .secondary)
        }
    }
}

struct TreeStructureView: View {
    let node: FolderNode
    @State private var isExpanded = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if !node.children.isEmpty {
                    Button(action: { isExpanded.toggle() }) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                Image(systemName: node.children.isEmpty ? "doc" : "folder")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                
                Text(node.url.lastPathComponent)
                    .font(.system(size: 12))
            }
            .padding(.vertical, 2)
            
            if isExpanded {
                ForEach(node.children) { child in
                    TreeStructureView(node: child)
                        .padding(.leading, 16)
                }
            }
        }
    }
}

struct PDFPreviewView: View {
    @ObservedObject var processor: FileProcessor
    let pdfDocument: PDFDocument?
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var zoomLevel: CGFloat = 1.0
    
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
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Divider()
            
            if let pdf = pdfDocument {
                PDFKitView(pdfDocument: pdf, zoomLevel: zoomLevel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    showSuccessNotification(url: url)
                }
            } catch {
                DispatchQueue.main.async {
                    self.showError = true
                    self.errorMessage = "Failed to save PDF: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func showSuccessNotification(url: URL) {
        let content = UNMutableNotificationContent()
        content.title = "PDF Saved"
        content.body = "Your PDF has been saved successfully"
        
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                          content: content,
                                          trigger: nil)
        
        UNUserNotificationCenter.current().add(request)
        NSWorkspace.shared.activateFileViewerSelecting([url])
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

struct PDFKitView: NSViewRepresentable {
    let pdfDocument: PDFDocument
    let zoomLevel: CGFloat
    
    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        configurePDFView(pdfView)
        return pdfView
    }
    
    func updateNSView(_ pdfView: PDFView, context: Context) {
        pdfView.document = pdfDocument
        pdfView.scaleFactor = zoomLevel
        pdfView.needsLayout = true
        pdfView.layoutDocumentView()
    }
    
    private func configurePDFView(_ pdfView: PDFView) {
        pdfView.document = pdfDocument
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.backgroundColor = .clear
        pdfView.displaysPageBreaks = true
        pdfView.displayDirection = .vertical
        pdfView.maxScaleFactor = 4.0
        pdfView.minScaleFactor = 0.25
        
        if let scrollView = pdfView.documentView?.enclosingScrollView {
            scrollView.hasVerticalScroller = true
            scrollView.scrollerStyle = .overlay
            scrollView.contentInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        }
    }
}
