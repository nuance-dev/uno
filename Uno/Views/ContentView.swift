import SwiftUI
import UniformTypeIdentifiers
import PDFKit
import os

private let logger = Logger(subsystem: "me.nuanc.Uno", category: "ContentView")

struct ContentView: View {
    @StateObject private var processor = FileProcessor()
    @State private var isDragging = false
    @State private var mode = Mode.prompt
    private let performanceMonitor = PerformanceMonitor.shared
    
    enum Mode: String, CaseIterable {
        case prompt = "Prompt"
        case pdf = "PDF"
    }
    
    var body: some View {
        ZStack {
            VisualEffectBlur(material: .headerView, blendingMode: .behindWindow)
                .ignoresSafeArea()
            
            VStack(spacing: 10) {
                modeSwitcher
                mainContent
            }
            .padding(30)
        }
        .frame(minWidth: 600, minHeight: 700)
        .onChange(of: mode, initial: true) { oldValue, newMode in
            processor.setMode(newMode)
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            handleDroppedFiles(providers)
        }
    }
    
    private var modeSwitcher: some View {
        HStack(spacing: 16) {
            HStack(spacing: 0) {
                ForEach([Mode.prompt, Mode.pdf], id: \.self) { tabMode in
                    Button(action: { 
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            mode = tabMode
                        }
                    }) {
                        Text(tabMode == .prompt ? "Prompt" : "PDF")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(mode == tabMode ? Color(NSColor.controlAccentColor) : Color.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(mode == tabMode ? Color(NSColor.controlAccentColor).opacity(0.1) : Color.clear)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .frame(width: 120)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.windowBackgroundColor).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .padding(.horizontal)
    }
    
    private var mainContent: some View {
        ZStack {
            if processor.files.isEmpty {
                DropZoneView(isDragging: $isDragging, mode: mode) {
                    handleFileSelection()
                }
            } else {
                ProcessedView(processor: processor, mode: mode)
            }
            
            if processor.isProcessing {
                LoaderView(progress: processor.progress)
            }
        }
    }
    
    func handleFileSelection() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        
        // Convert string file extensions to UTTypes
        if mode == .prompt {
            let types = processor.supportedTypes.compactMap { fileExtension in
                UTType(filenameExtension: fileExtension)
            }
            panel.allowedContentTypes = types
        } else {
            panel.allowedContentTypes = [.pdf, .text, .image]
        }
        
        panel.begin { response in
            if response == .OK {
                let urls = panel.urls
                processSelectedFiles(urls)
            }
        }
    }
    
    private func handleDroppedFiles(_ providers: [NSItemProvider]) -> Bool {
        logger.debug("Drop received with \(providers.count) items")
        let dispatchGroup = DispatchGroup()
        var urls: [URL] = []
        var success = false
        
        for provider in providers {
            dispatchGroup.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (urlData, error) in
                defer { dispatchGroup.leave() }
                
                if let error = error {
                    logger.error("Error loading dropped item: \(error.localizedDescription)")
                    return
                }
                
                if let urlData = urlData as? Data,
                   let path = String(data: urlData, encoding: .utf8),
                   let url = URL(string: path) {
                    logger.debug("Successfully loaded URL: \(url.path)")
                    urls.append(url)
                    success = true
                }
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            logger.debug("Processing \(urls.count) dropped files")
            processSelectedFiles(urls)
        }
        
        return success
    }
    
    private func processSelectedFiles(_ urls: [URL]) {
        performanceMonitor.trackOperation("processSelectedFiles") {
            logger.debug("Processing selected files: \(urls.map { $0.lastPathComponent })")
            processor.files.removeAll()
            
            for url in urls {
                autoreleasepool {
                    processFile(url)
                }
            }
            
            if !processor.files.isEmpty {
                logger.debug("Starting file processing with \(processor.files.count) files")
                DispatchQueue.main.async {
                    self.processor.processFiles(mode: self.mode)
                }
            }
        }
    }
    
    private func processFile(_ url: URL) {
        if processor.validateFile(url) {
            processor.files.append(url)
        }
    }
}
