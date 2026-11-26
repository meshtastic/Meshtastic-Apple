//
//  LabelPrinterTestView.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/25/26.
//

import CoreBluetooth
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Developers-only check of the Niimbot Bluetooth path: find a printer, connect, and print
/// a test label with a border, text and a QR, at the D110's 12 mm head.
struct LabelPrinterTestView: View {
	@StateObject private var printer = NiimbotPrinter()
	@AppStorage("labelPrinterTestLengthMM") private var lengthMM = 40
	@State private var message: String?

	private static let headDots = 96

	var body: some View {
		List {
			Section {
				LabeledContent("Status", value: statusText)
				Picker("Label length", selection: $lengthMM) {
					Text("30 mm").tag(30)
					Text("40 mm").tag(40)
				}
			}
			Section("Printers") {
				if printer.found.isEmpty {
					Text(printer.status == .searching ? "Searching…" : "None found yet")
						.foregroundStyle(.secondary)
				}
				ForEach(printer.found, id: \.identifier) { peripheral in
					Button(peripheral.name ?? "Unnamed") {
						Task { await run { try await printer.connect(peripheral) } }
					}
				}
				Button("Search") {
					Task { await run { try await printer.search() } }
				}
			}
			Section {
				Button("Print Test Label") {
					Task { await run { try await printer.printLabel(testBitmap()) } }
				}
				.disabled(!isReady)
				if let message {
					Text(message).foregroundStyle(.secondary)
				}
			}
			if let preview = testImage() {
				Section("Preview") {
					Image(decorative: preview, scale: 1)
						.interpolation(.none)
						.resizable()
						.aspectRatio(contentMode: .fit)
						.border(.gray)
				}
			}
		}
		.navigationTitle("Label Printer Test")
		.onDisappear { printer.disconnect() }
	}

	private var isReady: Bool {
		if case .ready = printer.status { return true }
		return false
	}

	private var statusText: String {
		switch printer.status {
		case .idle: "Not connected"
		case .bluetoothOff: "Bluetooth is off"
		case .searching: "Searching"
		case .connecting(let name): "Connecting to \(name)"
		case .ready(let name): "Connected to \(name)"
		case .printing(let name): "Printing on \(name)"
		case .failed(let reason): "Failed: \(reason)"
		}
	}

	private func run(_ work: () async throws -> Void) async {
		message = nil
		do {
			try await work()
		} catch {
			message = error.localizedDescription
		}
	}

	/// Label length in dots along the feed, as labeltastic sizes it: 8 per mm less 4 slack.
	private var lengthDots: Int { lengthMM * 8 - 4 }

	private func testBitmap() throws -> LabelBitmap {
		guard let image = testImage(), let bitmap = LabelBitmap(readingOrientation: image, headDots: Self.headDots) else {
			throw NiimbotPrinterError.noResponse(request: 0)
		}
		return bitmap
	}

	/// The test label in reading orientation: lengthDots x 96, one pixel per dot.
	private func testImage() -> CGImage? {
		let size = CGSize(width: lengthDots, height: Self.headDots)
		let format = UIGraphicsImageRendererFormat()
		format.scale = 1
		format.opaque = true
		let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
			UIColor.white.setFill()
			context.fill(CGRect(origin: .zero, size: size))
			UIColor.black.setStroke()
			context.stroke(CGRect(x: 4, y: 3, width: size.width - 8, height: size.height - 6))
			if let qr = qrCode("https://meshtastic.org", side: 80) {
				UIImage(cgImage: qr).draw(in: CGRect(x: 8, y: 8, width: 80, height: 80))
			}
			let title: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 22, weight: .bold)]
			let body: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 14, weight: .semibold)]
			"Meshtastic".draw(at: CGPoint(x: 96, y: 14), withAttributes: title)
			"D110 test, \(lengthMM) mm".draw(at: CGPoint(x: 96, y: 46), withAttributes: body)
			"Printed over BLE".draw(at: CGPoint(x: 96, y: 66), withAttributes: body)
		}
		return image.cgImage
	}

	/// A QR scaled by whole dots so its modules print evenly.
	private func qrCode(_ text: String, side: Int) -> CGImage? {
		let filter = CIFilter.qrCodeGenerator()
		filter.message = Data(text.utf8)
		filter.correctionLevel = "L"
		guard let output = filter.outputImage else { return nil }
		let scale = CGFloat(side / Int(output.extent.width))
		let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
		return CIContext().createCGImage(scaled, from: scaled.extent)
	}
}
