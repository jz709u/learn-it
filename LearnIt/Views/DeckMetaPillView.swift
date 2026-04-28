//
//  DeckMetaPillView.swift
//  AWSFlashcards
//
//  Created by Jay Zisch on 2026/04/20.
//
import SwiftUI

struct DeckMetaPillView: View {
    let label: String?
    let value: String
    init(label: String? = nil, value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let label {
                Text(label.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
