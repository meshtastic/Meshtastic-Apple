//
//  DeviceLinkDirectory.swift
//  Meshtastic
//

import SwiftUI
import SwiftData

struct DeviceLinkDirectory: View {
	@Query(sort: [SortDescriptor(\DeviceLinkEntity.shortCode)])
	var allLinks: [DeviceLinkEntity]
	@Environment(\.openURL) private var openURL

	var body: some View {
		List {
			if !allLinks.isEmpty {
				// The disclosure sits above the links it covers.
				Text("Product links may be affiliate links — purchases may earn Meshtastic a commission.")
					.font(.subheadline)
					.foregroundStyle(.secondary)
			}
			ForEach(allLinks, id: \.shortCode) { link in
				Button {
					if let url = URL(string: "https://msh.to/\(link.shortCode)") {
						openURL(url)
					}
				} label: {
					HStack {
						VStack(alignment: .leading, spacing: 2) {
							Text(link.linkDescription ?? link.shortCode)
								.font(.subheadline)
								.foregroundStyle(.primary)
							Text("msh.to/\(link.shortCode)")
								.font(.caption)
								.foregroundStyle(.secondary)
						}
						Spacer()
						Image(systemName: "safari")
							.foregroundStyle(.accent)
					}
				}
			}
		}
		.navigationTitle("Device Links")
		.navigationBarTitleDisplayMode(.large)
	}
}
