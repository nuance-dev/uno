import SwiftUI

struct SlideTransition: ViewModifier {
    let isPresented: Bool
    let edge: Edge
    
    func body(content: Content) -> some View {
        content
            .offset(x: offset.width, y: offset.height)
            .opacity(isPresented ? 1 : 0)
    }
    
    private var offset: CGSize {
        switch edge {
        case .leading:
            return CGSize(width: isPresented ? 0 : -20, height: 0)
        case .trailing:
            return CGSize(width: isPresented ? 0 : 20, height: 0)
        case .top:
            return CGSize(width: 0, height: isPresented ? 0 : -20)
        case .bottom:
            return CGSize(width: 0, height: isPresented ? 0 : 20)
        }
    }
}

extension View {
    func slideTransition(isPresented: Bool, edge: Edge = .leading) -> some View {
        modifier(SlideTransition(isPresented: isPresented, edge: edge))
    }
} 