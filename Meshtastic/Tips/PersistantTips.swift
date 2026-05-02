//
//  PersistantTips.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 6/19/25.
//
import SwiftUI
import TipKit

struct PersistentTip: TipViewStyle {
	func makeBody(configuration: Configuration) -> some View {
		HStack(alignment: .top, spacing: 14) {
			if let image = configuration.image {
				image
					.font(.system(size: 28, weight: .medium))
					.foregroundStyle(.tint)
					.frame(width: 44, height: 44)
					.background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
			}
			VStack(alignment: .leading, spacing: 4) {
				if let title = configuration.title {
					title
						.font(.subheadline)
						.fontWeight(.semibold)
				}
				if let message = configuration.message {
					message
						.font(.caption)
						.foregroundStyle(.secondary)
						.fixedSize(horizontal: false, vertical: true)
				}
				if !configuration.actions.isEmpty {
					HStack(spacing: 12) {
						ForEach(configuration.actions) { action in
							Button(action: action.handler) {
								action.label()
									.font(.caption)
									.fontWeight(.medium)
							}
							.buttonStyle(.bordered)
							.buttonBorderShape(.capsule)
							.controlSize(.small)
						}
					}
					.padding(.top, 4)
				}
			}
		}
		.padding(14)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
		.overlay(
			RoundedRectangle(cornerRadius: 14)
				.strokeBorder(.quaternary, lineWidth: 0.5)
		)
	}
}
