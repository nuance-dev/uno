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
    @Environment(\.colorScheme) private var colorScheme
    
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
                        .foregroundColor(.primary)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.1 : 0.08))
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .popover(isPresented: $showSettings, arrowEdge: .top) {
                    settingsView
                }
                .keyboardShortcut(",", modifiers: .command)
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
                    HStack(spacing: 8) {
                        Image(systemName: tabMode == .prompt ? "text.alignleft" : "doc.richtext")
                            .font(.system(size: 12))
                        Text(tabMode == .prompt ? "Prompt" : "PDF")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .frame(width: 110, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(mode == tabMode ? 
                                Color.accentColor.opacity(colorScheme == .dark ? 0.3 : 0.2) : 
                                Color.clear)
                    )
                    .foregroundColor(mode == tabMode ? 
                        Color.accentColor : 
                        Color.primary.opacity(0.7))
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(colorScheme == .dark ? 0.1 : 0.06))
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
    
    private var settingsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.headline)
                .padding(.bottom, 4)
            
            VStack(alignment: .leading, spacing: 8) {
                // Common settings for both modes
                Toggle("Use Syntax Highlighting", isOn: $processor.useSyntaxHighlighting)
                    .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                    .onChange(of: processor.useSyntaxHighlighting) { oldValue, newValue in
                        if !processor.files.isEmpty {
                            processor.processFiles(mode: mode)
                        }
                    }
                
                Toggle("Include File Tree", isOn: $processor.includeFileTree)
                    .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                    .onChange(of: processor.includeFileTree) { oldValue, newValue in
                        if !processor.files.isEmpty {
                            processor.processFiles(mode: mode)
                        }
                    }
                
                // Mode-specific settings
                if mode == .prompt {
                    Divider()
                    
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
                } else if mode == .pdf {
                    Divider()
                    
                    Text("PDF Theme")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Picker("Theme", selection: $processor.pdfTheme) {
                        ForEach(FileProcessor.PDFTheme.allCases) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .onChange(of: processor.pdfTheme) { oldValue, newValue in
                        if !processor.files.isEmpty {
                            processor.processFiles(mode: mode)
                        }
                    }
                    
                    HStack {
                        Text("Preview")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        // Theme preview
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(nsColor: themePreviewBackgroundColor(for: processor.pdfTheme)))
                            .frame(width: 180, height: 24)
                            .overlay(
                                Text("function example() { }")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(Color(nsColor: themePreviewTextColor(for: processor.pdfTheme)))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
                            )
                    }
                }
            }
        }
        .frame(width: 300)
        .padding(16)
    }
    
    private func themePreviewBackgroundColor(for theme: FileProcessor.PDFTheme) -> NSColor {
        switch theme {
        case .light, .github: return NSColor(calibratedRed: 0.98, green: 0.98, blue: 0.98, alpha: 1.0)
        case .dark: return NSColor(calibratedRed: 0.2, green: 0.22, blue: 0.25, alpha: 1.0)
        case .monokai: return NSColor(calibratedRed: 0.17, green: 0.18, blue: 0.16, alpha: 1.0)
        case .solarizedLight: return NSColor(calibratedRed: 0.95, green: 0.93, blue: 0.86, alpha: 1.0)
        }
    }
    
    private func themePreviewTextColor(for theme: FileProcessor.PDFTheme) -> NSColor {
        switch theme {
        case .light, .github, .solarizedLight: return .black
        case .dark, .monokai: return .white
        }
    }
}
