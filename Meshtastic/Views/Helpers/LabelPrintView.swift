//
//  LabelPrintView.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/25/26.
//

import CoreBluetooth
import MeshtasticProtobufs
import SwiftUI

/// Prints a label on a Niimbot D110 over Bluetooth: a preview, the label length, the
/// printer, and Print. Remembers the printer and the length. Share Contact prints a name
/// tag with it, Share Channels a channel label.
struct LabelPrintView: View {
	let title: String
	let previewDescription: String
	/// Draws the label in reading orientation for a length in dots, or throws why it can't.
	let render: (_ lengthDots: Int) throws -> CGImage?

	@StateObject private var printer = NiimbotPrinter()
	@AppStorage("nameTagLabelLengthMM") private var lengthMM = 40
	@AppStorage("nameTagPrinterID") private var printerID = ""
	@State private var message: String?
	@State private var printed = false

	var body: some View {
		NavigationStack {
			List {
				Section {
					switch label {
					case .success(let image?):
						Image(decorative: image, scale: 1)
							.interpolation(.none)
							.resizable()
							.aspectRatio(contentMode: .fit)
							.overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.4)))
							.accessibilityLabel(Text(previewDescription))
					case .failure(let error):
						Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
							.foregroundStyle(.secondary)
					default:
						EmptyView()
					}
					Picker("Label Length", selection: $lengthMM) {
						Text("30 mm").tag(30)
						Text("40 mm").tag(40)
					}
				} footer: {
					Text("For 12 mm die-cut labels on a Niimbot D110.")
				}

				Section("Printer") {
					switch printer.status {
					case .ready(let name), .printing(let name):
						Label(name, systemImage: "printer.fill")
					case .connecting(let name):
						Label("Connecting to \(name)…", systemImage: "printer")
					case .bluetoothOff:
						Label("Turn on Bluetooth to find the printer.", systemImage: "exclamationmark.triangle")
					default:
						if printer.found.isEmpty {
							Label("Searching… Turn the printer on and close the Niimbot app.", systemImage: "magnifyingglass")
								.foregroundStyle(.secondary)
						}
						ForEach(printer.found, id: \.identifier) { peripheral in
							Button(peripheral.name ?? String(localized: "Printer")) {
								Task { await connect(peripheral) }
							}
						}
					}
				}

				Section {
					Button {
						Task { await printLabel() }
					} label: {
						if case .printing = printer.status {
							Label("Printing…", systemImage: "printer")
						} else {
							Label(printed ? "Print Another" : "Print", systemImage: "printer")
						}
					}
					.disabled(!canPrint)
					if let message {
						Text(message)
							.foregroundStyle(.secondary)
					}
				}
			}
			.navigationTitle(title)
			.navigationBarTitleDisplayMode(.inline)
			.sheetCloseButton()
		}
		.task { await start() }
		.onDisappear { printer.disconnect() }
	}

	private var label: Result<CGImage?, Error> {
		Result { try render(NameTagRenderer.lengthDots(millimeters: lengthMM)) }
	}

	private var canPrint: Bool {
		guard case .ready = printer.status, case .success(.some) = label else { return false }
		return true
	}

	/// Reconnects to the printer used last time, or searches for one.
	private func start() async {
		do {
			if let id = UUID(uuidString: printerID), try await printer.connect(identifier: id) {
				return
			}
		} catch {
			// The remembered printer is off or out of range: look for any nearby.
		}
		do {
			try await printer.search()
		} catch {
			message = error.localizedDescription
		}
	}

	private func connect(_ peripheral: CBPeripheral) async {
		message = nil
		do {
			try await printer.connect(peripheral)
			printerID = peripheral.identifier.uuidString
		} catch {
			message = error.localizedDescription
			try? await printer.search()
		}
	}

	private func printLabel() async {
		message = nil
		guard case .success(let image?) = label,
			  let bitmap = LabelBitmap(readingOrientation: image, headDots: NameTagRenderer.headDots) else { return }
		do {
			try await printer.printLabel(bitmap)
			printed = true
		} catch {
			message = error.localizedDescription
		}
	}
}

extension LabelPrintView {
	/// A node's contact as a name tag.
	init(nameTagFor node: NodeInfo) {
		self.init(
			title: String(localized: "Print Name Tag"),
			previewDescription: String(localized: "Name tag preview for \(node.user.longName)")
		) { length in
			NameTagRenderer.image(for: NameTagContent(node: node), lengthDots: length)
		}
	}

	/// Shared channels as a label anyone can scan to join.
	init(channelLabelFor content: ChannelLabelContent) {
		self.init(
			title: String(localized: "Print Channel Label"),
			previewDescription: String(localized: "Channel label preview for \(content.title)")
		) { length in
			try ChannelLabelRenderer.image(for: content, lengthDots: length)
		}
	}
}
