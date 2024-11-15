//
//  MainContent.swift
//  ArchiveExtractor
//
//  Created by Ivan Apostolovski on 14.11.24.
//

import SwiftUI

struct MainContent: View {
    let isExtracting: Bool
    let progress: Double

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.zipper")
                .font(.system(size: 48))
                .foregroundColor(.blue)

            if isExtracting {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 200)
                Text("\(Int(progress * 100))%")
                Text("Extracting...")
            } else {
                Text("Drop archive here")
                    .font(.title2)
                Text("Supports ZIP, RAR, 7Z, TAR, GZ")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(40)
    }
}
