import AppKit

extension NSPasteboard {
    func getImageFromPasteboard() -> NSImage? {
        if let image = NSImage(pasteboard: self) {
            return image
        }
        
        // Try reading from file URL if image is not directly available
        if let url = self.pasteboardItems?.first?.string(forType: .fileURL),
           let fileURL = URL(string: url),
           let image = NSImage(contentsOf: fileURL) {
            return image
        }
        
        return nil
    }
}
