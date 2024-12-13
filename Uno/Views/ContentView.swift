import SwiftUI
import UniformTypeIdentifiers
import PDFKit
import os

private let logger = Logger(subsystem: "me.nuanc.Uno", category: "ContentView")

struct ContentView: View {
    @StateObject private var processor = FileProcessor()
    @State private var isDragging = false
    @State private var mode = Mode.prompt
    @State private var showClearConfirmation = false
    
    enum Mode: String, CaseIterable {
        case prompt = "Prompt"
        case pdf = "PDF"
    }
    
    var body: some View {
        ZStack {
            VisualEffectBlur(material: .contentBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                // Top toolbar
                HStack {
                    modeSwitcher
                    
                    Spacer()
                    
                    if !processor.files.isEmpty {
                        Button(action: { showClearConfirmation = true }) {
                            Label("Clear All", systemImage: "trash")
                                .foregroundColor(.red)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.borderless)
                        .keyboardShortcut(.delete, modifiers: [.command])
                    }
                }
                .padding(.horizontal)
                .padding(.top, 20)
                
                // Main content
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
            .padding(20)
        }
        .alert("Clear All Files?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                withAnimation {
                    processor.clearFiles()
                }
            }
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
        processor.files.removeAll()
        
        for url in urls {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                let files = processor.processDirectory(url)
                processor.files.append(contentsOf: files)
            } else {
                processFile(url)
            }
        }
        
        if !processor.files.isEmpty {
            processor.processFiles(mode: mode)
        }
    }
    
    private func processFile(_ url: URL) {
        if processor.validateFile(url) {
            processor.files.append(url)
        }
    }
}
