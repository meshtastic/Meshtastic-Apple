//
//  LogDetail.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 6/5/24.
//

import SwiftUI
import MapKit
import OSLog

@available(iOS 17.0, macOS 14.0, *)
struct LogDetail: View {

	@Environment(\.dismiss) private var dismiss
	private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
	var log: OSLogEntryLog

	var body: some View {

		VStack {
			HStack {
				Text("OS Log Entry Details")
					.font(.largeTitle)
			}
			Divider()
			HStack(alignment: .top) {
				VStack(alignment: .leading) {
					List {
						/// Time
						Label {
							Text("time".localized + ":")
								.font(idiom == .phone ? .callout : .title)
							LastHeardText(lastHeard: log.date)
								.font(idiom == .phone ? .callout : .title)
						} icon: {
							Image(systemName: "timer")
								.symbolRenderingMode(.hierarchical)
								.font(idiom == .phone ? .callout : .title)
								.frame(width: 35)
						}
						.padding(.bottom, 5)
						.listRowSeparator(.visible)
						/// Subsystem
						Label {
							Text("subsystem".localized + ":")
								.font(idiom == .phone ? .callout : .title)
							Text(log.subsystem)
								.font(idiom == .phone ? .callout : .title)
						} icon: {
							Image(systemName: "gear")
								.symbolRenderingMode(.hierarchical)
								.font(idiom == .phone ? .callout : .title)
								.frame(width: 35)
						}
						.padding(.bottom, 5)
						.listRowSeparator(.visible)
						/// Process
						Label {
							Text("process".localized + ":")
								.font(idiom == .phone ? .callout : .title)
							Text(log.process)
								.font(idiom == .phone ? .callout : .title)
						} icon: {
							Image(systemName: "tag")
								.symbolRenderingMode(.hierarchical)
								.font(idiom == .phone ? .callout : .title)
								.frame(width: 35)
						}
						.padding(.bottom, 5)
						.listRowSeparator(.visible)
						/// Category
						Label {
							Text("category".localized + ":")
								.font(idiom == .phone ? .callout : .title)
							Text(log.category)
								.font(idiom == .phone ? .callout : .title)
						} icon: {
							Image(systemName: "rectangle.3.group")
								.symbolRenderingMode(.hierarchical)
								.font(idiom == .phone ? .callout : .title)
								.frame(width: 35)
						}
						.padding(.bottom, 5)
						.listRowSeparator(.visible)
						/// Level
						Label {
							Text("level".localized + ":")
								.font(idiom == .phone ? .callout : .title)
							Text(log.level.description)
								.font(idiom == .phone ? .callout : .title)
						} icon: {
							Image(systemName: "shield")
								.symbolRenderingMode(.hierarchical)
								.font(idiom == .phone ? .callout : .title)
								.frame(width: 35)
						}
						.padding(.bottom, 5)
						.listRowSeparator(.visible)
						/// message
						Label {
							Text("message".localized + ":")
								.font(idiom == .phone ? .callout : .title)
						
						} icon: {
							Image(systemName: "text.bubble")
								.symbolRenderingMode(.hierarchical)
								.font(idiom == .phone ? .callout : .title)
								.frame(width: 35)
						}
						.listRowSeparator(.hidden)
						Text(log.composedMessage)
							.font(idiom == .phone ? .callout : .title)
							.padding(.bottom, 5)
					}
					.listStyle(.plain)
				}
				Spacer()
			}
			.padding(.top)
#if targetEnvironment(macCatalyst)
			Spacer()
			Button {
				dismiss()
			} label: {
				Label("close", systemImage: "xmark")
			}
			.buttonStyle(.bordered)
			.buttonBorderShape(.capsule)
			.controlSize(.large)
			.padding(.bottom)
#endif
		}
		.presentationDetents([.fraction(0.65), .fraction(0.75), .fraction(0.85)])
		.presentationDragIndicator(.visible)
	}
}
