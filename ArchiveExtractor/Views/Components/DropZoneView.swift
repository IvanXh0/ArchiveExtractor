//
//  DropZoneView.swift
//  ArchiveExtractor
//
//  Created by Ivan Apostolovski on 14.11.24.
//

import SwiftUI

struct DropZoneView<Content: View>: View {
    @Binding var isDragActive: Bool
    let content: Content

    init(isDragActive: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self._isDragActive = isDragActive
        self.content = content()
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(isDragActive ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [10]))
                    .foregroundColor(isDragActive ? .blue : .gray)
            )
            .overlay(content)
    }
}
