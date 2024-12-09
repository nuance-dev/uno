import SwiftUI
import UniformTypeIdentifiers
import PDFKit

struct ContentView: View {
    @StateObject private var processor = FileProcessor()
    @State private var isDragging = false
    @State private var mode = Mode.prompt
    
    enum Mode: Hashable {
        case prompt
        case pdf
    }
    
    var body: some View {
        ZStack {
            VisualEffectBlur(material: .headerView, blendingMode: .behindWindow)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Mode Switcher
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
                                    .foregroundColor(mode == tabMode ? 
                                        Color(NSColor.controlAccentColor) : 
                                        Color.secondary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 36)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(mode == tabMode ? 
                                                Color(NSColor.controlAccentColor).opacity(0.1) : 
                                                Color.clear)
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
                
                // Main Content Area
                ZStack {
                    if processor.files.isEmpty {
                        DropZoneView(isDragging: $isDragging, mode: mode) {
                            handleFileSelection()
                        }
                    } else {
                        ProcessingView(processor: processor, mode: mode)
                    }
                    
                    if processor.isProcessing {
                        LoaderView()
                    }
                }
            }
            .padding(30)
        }
        .frame(minWidth: 600, minHeight: 700)
        .onDrop(of: [.item], isTargeted: $isDragging) { providers in
            handleDroppedFiles(providers)
            return true
        }
    }
    
    // File handling methods will follow...
}
