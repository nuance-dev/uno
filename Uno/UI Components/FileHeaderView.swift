import SwiftUI

struct FileHeaderView: View {
    @ObservedObject var processor: FileProcessor
    @Binding var hoveredFile: URL?
    @Binding var draggedItem: URL?
    @Binding var showClearConfirmation: Bool
    
    var body: some View {
        ZStack {
            VisualEffectBlur(material: .headerView, blendingMode: .behindWindow)
                .edgesIgnoringSafeArea(.horizontal)
            
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(processor.files, id: \.self) { file in
                            FileTag(
                                url: file,
                                onRemove: {
                                    withAnimation(.spring(response: 0.3)) {
                                        processor.removeFile(file)
                                    }
                                },
                                draggedItem: $draggedItem,
                                items: processor.files,
                                reorderHandler: processor.moveFile
                            )
                            .scaleEffect(hoveredFile == file ? 0.98 : 1)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                
                if !processor.files.isEmpty {
                    HStack {
                        Spacer()
                        Button(action: { showClearConfirmation = true }) {
                            Label("Clear All", systemImage: "trash")
                                .font(.system(size: 12))
                                .foregroundColor(.red.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 16)
                        .padding(.bottom, 8)
                    }
                }
            }
        }
        .frame(height: processor.files.isEmpty ? 52 : 90)
    }
} 