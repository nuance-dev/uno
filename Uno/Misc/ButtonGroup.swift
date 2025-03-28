// ButtonGroup.swift
import SwiftUI

struct ToolbarButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    // Removed isFirst, isLast

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .imageScale(.medium) // Use imageScale
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 16)
            .frame(maxHeight: .infinity) // Fill height
        }
        .buttonStyle(.plain) // Keep plain style for toolbar look
        .contentShape(Rectangle())
    }
}

struct ButtonDivider: View {
    var body: some View {
        Divider()
            .frame(height: 20) // Adjust height to match button content area
    }
}

struct ButtonGroup: View {
    let buttons: [(title: String, icon: String, action: () -> Void)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(buttons.enumerated()), id: \.offset) { index, button in
                if index > 0 {
                    ButtonDivider()
                }
                ToolbarButton(
                    title: button.title,
                    icon: button.icon,
                    action: button.action
                )
            }
        }
        .fixedSize(horizontal: false, vertical: true) // Constrain height
        .frame(height: 32) // Set a standard height for the group
        // Use standard material for background + subtle border
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
         .overlay(
             RoundedRectangle(cornerRadius: 8)
                 .stroke(.separator.opacity(0.5), lineWidth: 1) // Use semantic color
         )
    }
} 