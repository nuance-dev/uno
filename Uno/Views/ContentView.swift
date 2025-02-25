import SwiftUI
import UniformTypeIdentifiers
import PDFKit
import os

private let logger = Logger(subsystem: "me.nuanc.Uno", category: "ContentView")

struct ContentView: View {
    @StateObject private var processor = FileProcessor()
    @State private var isDragging = false
    @State private var mode = Mode.prompt
    @State private var showSettings = false
    @State private var isAnimating = false
    
    enum Mode: Hashable {
        case prompt
        case pdf
    }
    
    var body: some View {
        ZStack {
            // Frosted glass background
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                appHeader
                
                Divider()
                    .opacity(0.2)
                    .padding(.horizontal)
                
                mainContent
            }
            .padding(.vertical, 20)
        }
        .frame(minWidth: 700, minHeight: 700)
        .preferredColorScheme(.dark)
        .onChange(of: mode, initial: true) { oldValue, newMode in
            processor.setMode(newMode)
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            handleDroppedFiles(providers)
        }
    }
    
    private var appHeader: some View {
        HStack(spacing: 20) {
            // Mode switcher
            modeSwitcher
            
            Spacer()
            
            // Settings button (only visible when files are loaded)
            if !processor.files.isEmpty {
                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.accentColor.opacity(0.1))
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .popover(isPresented: $showSettings, arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Settings")
                            .font(.headline)
                            .padding(.bottom, 4)
                        
                        Group {
                            // Common settings for both modes
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Display")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                Toggle("Syntax Highlighting", isOn: $processor.useSyntaxHighlighting)
                                    .toggleStyle(SwitchToggleStyle())
                                    .onChange(of: processor.useSyntaxHighlighting) { oldValue, newValue in
                                        // Reprocess files to apply syntax highlighting change
                                        if !processor.files.isEmpty {
                                            processor.processFiles(mode: mode)
                                        }
                                    }
                            }
                            
                            Divider()
                                .padding(.vertical, 8)
                        }
                        
                        if mode == .prompt {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Prompt Format")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                Picker("Format", selection: $processor.promptFormat) {
                                    ForEach(FileProcessor.PromptFormat.allCases) { format in
                                        Text(format.rawValue).tag(format)
                                    }
                                }
                                .pickerStyle(SegmentedPickerStyle())
                                .onChange(of: processor.promptFormat) { oldValue, newValue in
                                    if !processor.files.isEmpty {
                                        processor.processFiles(mode: mode)
                                    }
                                }
                                
                                Toggle("Include File Tree", isOn: $processor.includeFileTree)
                                    .toggleStyle(SwitchToggleStyle())
                                    .onChange(of: processor.includeFileTree) { oldValue, newValue in
                                        if !processor.files.isEmpty {
                                            processor.processFiles(mode: mode)
                                        }
                                    }
                            }
                        }
                    }
                    .padding()
                    .frame(width: 280)
                }
            }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 10)
    }
    
    private var modeSwitcher: some View {
        HStack(spacing: 0) {
            ForEach([Mode.prompt, Mode.pdf], id: \.self) { tabMode in
                Button(action: { 
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        mode = tabMode
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: tabMode == .prompt ? "text.alignleft" : "doc.richtext")
                            .font(.system(size: 12))
                        Text(tabMode == .prompt ? "Prompt" : "PDF")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .frame(width: 100, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(mode == tabMode ? Color.accentColor : Color.clear)
                            .opacity(mode == tabMode ? 0.2 : 0)
                    )
                    .foregroundColor(mode == tabMode ? Color.accentColor : Color.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.1))
        )
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
        .padding(.horizontal, 30)
        .padding(.top, 20)
    }
    
    func handleFileSelection() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        
        // Define allowed content types based on mode
        let allowedTypes: [UTType] = mode == .prompt ? 
            [.plainText, .sourceCode, .html, .yaml, .json, .xml, .propertyList, .pdf] :
            [.plainText, .pdf, .image, .html, .rtf, .rtfd]
        
        panel.allowedContentTypes = allowedTypes
        
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
        logger.debug("Processing selected files: \(urls.map { $0.lastPathComponent })")
        processor.files.removeAll() // Clear existing files
        
        for url in urls {
            if url.hasDirectoryPath {
                logger.debug("Processing directory: \(url.path)")
                if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey]) {
                    for case let fileURL as URL in enumerator {
                        if processor.supportedTypes.contains(fileURL.pathExtension.lowercased()) {
                            logger.debug("Adding file from directory: \(fileURL.lastPathComponent)")
                            processor.files.append(fileURL)
                        }
                    }
                }
            } else {
                if processor.supportedTypes.contains(url.pathExtension.lowercased()) {
                    logger.debug("Adding single file: \(url.lastPathComponent)")
                    processor.files.append(url)
                }
            }
        }
        
        if !processor.files.isEmpty {
            logger.debug("Starting file processing with \(processor.files.count) files in mode: \(String(describing: mode))")
            DispatchQueue.main.async {
                self.processor.processFiles(mode: self.mode)
            }
        } else {
            logger.warning("No valid files found to process")
        }
    }
}
