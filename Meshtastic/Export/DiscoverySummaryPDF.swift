// MARK: DiscoverySummaryPDF
//
//  DiscoverySummaryPDF.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 2026.
//

import MapKit
import OSLog
import SwiftUI
import UniformTypeIdentifiers

// MARK: - PDF FileDocument

struct PDFDocument: FileDocument {
	static let readableContentTypes = [UTType.pdf]

	let pdfData: Data

	init(data: Data) {
		pdfData = data
	}

	init(configuration: ReadConfiguration) throws {
		if let data = configuration.file.regularFileContents {
			pdfData = data
		} else {
			throw CocoaError(.fileReadCorruptFile)
		}
	}

	func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
		FileWrapper(regularFileWithContents: pdfData)
	}
}

// MARK: - Discovery Summary PDF Generator

enum DiscoverySummaryPDF {

	// MARK: Explicit colors for PDF rendering (dynamic UIColors are invisible in PDF context)
	private static let black = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
	private static let darkGray = UIColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1)
	private static let medGray = UIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
	private static let lightGray = UIColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1)
	private static let accentGreen = UIColor(red: 0.36, green: 0.68, blue: 0.36, alpha: 1)
	private static let headerBg = UIColor(red: 0.22, green: 0.56, blue: 0.24, alpha: 1)

	static func generate(session: DiscoverySessionEntity) async -> Data {
		// Capture map snapshot before PDF rendering
		let mapImage = await snapshotMap(session: session)

		let pageWidth: CGFloat = 612 // US Letter
		let pageHeight: CGFloat = 792
		let margin: CGFloat = 48
		let contentWidth = pageWidth - margin * 2

		let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

		return renderer.pdfData { context in
			var y: CGFloat = 0
			var pageNumber = 0

			// MARK: Fonts

			let titleFont = UIFont.systemFont(ofSize: 20, weight: .bold)
			let subtitleFont = UIFont.systemFont(ofSize: 11, weight: .medium)
			let headingFont = UIFont.systemFont(ofSize: 14, weight: .bold)
			let bodyFont = UIFont.systemFont(ofSize: 10, weight: .regular)
			let bodyBoldFont = UIFont.systemFont(ofSize: 10, weight: .semibold)
			let captionFont = UIFont.systemFont(ofSize: 8.5, weight: .regular)
			let presetTitleFont = UIFont.systemFont(ofSize: 12, weight: .bold)
			let statValueFont = UIFont.systemFont(ofSize: 10, weight: .bold)

			// MARK: Drawing Helpers

			func newPage() {
				context.beginPage()
				pageNumber += 1
				y = margin
			}

			func checkPage(needed: CGFloat) {
				if y + needed > pageHeight - margin - 20 {
					drawPageFooter()
					newPage()
				}
			}

			func drawPageFooter() {
				let footerY = pageHeight - margin + 4
				let footerAttrs: [NSAttributedString.Key: Any] = [.font: captionFont, .foregroundColor: medGray]
				let leftText = NSAttributedString(string: "Meshtastic Discovery Scan Report", attributes: footerAttrs)
				let rightText = NSAttributedString(string: "Page \(pageNumber)", attributes: footerAttrs)

				// Separator line
				let path = UIBezierPath()
				path.move(to: CGPoint(x: margin, y: footerY - 4))
				path.addLine(to: CGPoint(x: pageWidth - margin, y: footerY - 4))
				lightGray.setStroke()
				path.lineWidth = 0.5
				path.stroke()

				leftText.draw(at: CGPoint(x: margin, y: footerY))
				let rightSize = rightText.size()
				rightText.draw(at: CGPoint(x: pageWidth - margin - rightSize.width, y: footerY))
			}

			func drawText(_ text: String, x: CGFloat = margin, attrs: [NSAttributedString.Key: Any], maxWidth: CGFloat? = nil) {
				let w = maxWidth ?? (contentWidth - (x - margin))
				let attrStr = NSAttributedString(string: text, attributes: attrs)
				let boundingRect = attrStr.boundingRect(with: CGSize(width: w, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
				checkPage(needed: boundingRect.height + 2)
				attrStr.draw(in: CGRect(x: x, y: y, width: w, height: boundingRect.height + 2))
				y += boundingRect.height + 3
			}

			func drawRow(_ label: String, _ value: String, indent: CGFloat = 0) {
				let labelX = margin + indent
				let labelWidth: CGFloat = 180
				let valueX = labelX + labelWidth
				let valueWidth: CGFloat = contentWidth - labelWidth - indent
				let labelAttrs: [NSAttributedString.Key: Any] = [.font: bodyFont, .foregroundColor: darkGray]
				let valueAttrs: [NSAttributedString.Key: Any] = [.font: bodyBoldFont, .foregroundColor: black]
				let labelStr = NSAttributedString(string: label, attributes: labelAttrs)
				let valueStr = NSAttributedString(string: value, attributes: valueAttrs)
				let labelH = labelStr.boundingRect(with: CGSize(width: labelWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], context: nil).height
				let valueH = valueStr.boundingRect(with: CGSize(width: valueWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], context: nil).height
				let rowH = max(labelH, valueH) + 3
				checkPage(needed: rowH)
				labelStr.draw(in: CGRect(x: labelX, y: y, width: labelWidth, height: rowH))
				valueStr.draw(in: CGRect(x: valueX, y: y, width: valueWidth, height: rowH))
				y += rowH
			}

			func drawSectionHeading(_ title: String) {
				checkPage(needed: 28)
				y += 6

				// Green accent bar + heading text
				let barRect = CGRect(x: margin, y: y, width: 3, height: 16)
				headerBg.setFill()
				UIBezierPath(roundedRect: barRect, cornerRadius: 1.5).fill()

				let headAttrs: [NSAttributedString.Key: Any] = [.font: headingFont, .foregroundColor: black]
				let headStr = NSAttributedString(string: title, attributes: headAttrs)
				headStr.draw(at: CGPoint(x: margin + 10, y: y))
				y += 20

				// Thin separator
				let path = UIBezierPath()
				path.move(to: CGPoint(x: margin, y: y))
				path.addLine(to: CGPoint(x: pageWidth - margin, y: y))
				lightGray.setStroke()
				path.lineWidth = 0.5
				path.stroke()
				y += 6
			}

			func drawStatPair(_ label: String, _ value: String, x: CGFloat) {
				let labelAttrs: [NSAttributedString.Key: Any] = [.font: captionFont, .foregroundColor: medGray]
				let valueAttrs: [NSAttributedString.Key: Any] = [.font: statValueFont, .foregroundColor: black]
				let labelStr = NSAttributedString(string: label, attributes: labelAttrs)
				let valueStr = NSAttributedString(string: value, attributes: valueAttrs)
				labelStr.draw(at: CGPoint(x: x, y: y))
				valueStr.draw(at: CGPoint(x: x, y: y + 11))
			}

			// MARK: Page 1 — Header Banner

			newPage()

			// Green header banner
			let bannerHeight: CGFloat = 60
			let bannerRect = CGRect(x: 0, y: 0, width: pageWidth, height: bannerHeight)
			headerBg.setFill()
			UIBezierPath(rect: bannerRect).fill()

			// Logo (native aspect ratio 100:55)
			let logoHeight: CGFloat = 32
			let logoWidth: CGFloat = logoHeight * (100.0 / 55.0)
			var textX = margin
			if let logo = UIImage(named: "logo-white") {
				let logoY = (bannerHeight - logoHeight) / 2
				logo.draw(in: CGRect(x: margin, y: logoY, width: logoWidth, height: logoHeight))
				textX = margin + logoWidth + 10
			}

			let bannerTitleAttrs: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: UIColor.white]
			let bannerSubAttrs: [NSAttributedString.Key: Any] = [.font: subtitleFont, .foregroundColor: UIColor(white: 1.0, alpha: 0.85)]

			let bannerTitle = NSAttributedString(string: "Meshtastic Discovery Scan Report", attributes: bannerTitleAttrs)
			bannerTitle.draw(at: CGPoint(x: textX, y: 14))
			let bannerDate = NSAttributedString(string: session.timestamp.formatted(date: .long, time: .shortened), attributes: bannerSubAttrs)
			bannerDate.draw(at: CGPoint(x: textX, y: 38))

			y = bannerHeight + 16

			// MARK: Session Overview

			drawSectionHeading("Session Overview")
			drawRow("Presets Scanned", session.presetsScanned.replacingOccurrences(of: ",", with: ", "))
			drawRow("Total Unique Nodes", "\(session.totalUniqueNodes)")
			drawRow("Text Messages", "\(session.totalTextMessages)")
			drawRow("Sensor Packets", "\(session.totalSensorPackets)")
			if session.furthestNodeDistance > 0 {
				drawRow("Furthest Node", formatDistance(session.furthestNodeDistance))
			}
			if session.averageChannelUtilization > 0 {
				drawRow("Avg Channel Utilization", String(format: "%.1f%%", session.averageChannelUtilization))
			}
			drawRow("Status", session.completionStatus.capitalized)

			// MARK: Map Snapshot

			if let mapImage {
				let mapHeight: CGFloat = 280
				checkPage(needed: mapHeight + 16)
				y += 8

				// Draw map with rounded corners and border
				let mapRect = CGRect(x: margin, y: y, width: contentWidth, height: mapHeight)
				let clipPath = UIBezierPath(roundedRect: mapRect, cornerRadius: 6)
				context.cgContext.saveGState()
				clipPath.addClip()
				mapImage.draw(in: mapRect)
				context.cgContext.restoreGState()

				// Border
				lightGray.setStroke()
				UIBezierPath(roundedRect: mapRect, cornerRadius: 6).lineWidth = 1
				UIBezierPath(roundedRect: mapRect, cornerRadius: 6).stroke()

				y += mapHeight + 10
			}

			// MARK: Per-Preset Results

			drawSectionHeading("Per-Preset Results")

			for result in session.presetResults {
				checkPage(needed: 90)

				// Preset name with node count badge
				let presetAttrs: [NSAttributedString.Key: Any] = [.font: presetTitleFont, .foregroundColor: black]
				let presetStr = NSAttributedString(string: result.presetName, attributes: presetAttrs)
				presetStr.draw(at: CGPoint(x: margin + 4, y: y))

				let badgeText = "\(result.uniqueNodesFound) nodes"
				let badgeAttrs: [NSAttributedString.Key: Any] = [.font: bodyBoldFont, .foregroundColor: result.uniqueNodesFound > 0 ? accentGreen : medGray]
				let badgeStr = NSAttributedString(string: badgeText, attributes: badgeAttrs)
				let badgeSize = badgeStr.size()
				badgeStr.draw(at: CGPoint(x: pageWidth - margin - badgeSize.width, y: y + 1))
				y += 18

				// Two-column stat cards
				let colWidth: CGFloat = contentWidth * 0.25
				let col1 = margin + 4
				let col2 = margin + colWidth
				let col3 = margin + colWidth * 2
				let col4 = margin + colWidth * 3

				drawStatPair("Direct", "\(result.directNeighborCount)", x: col1)
				drawStatPair("Mesh", "\(result.meshNeighborCount)", x: col2)
				drawStatPair("Infrastructure", "\(result.infrastructureNodeCount)", x: col3)
				drawStatPair("Messages", "\(result.messageCount)", x: col4)
				y += 26

				drawStatPair("Sensor Pkts", "\(result.sensorPacketCount)", x: col1)
				drawStatPair("Ch Util", result.averageChannelUtilization > 0 ? String(format: "%.1f%%", result.averageChannelUtilization) : "—", x: col2)
				drawStatPair("Airtime", result.averageAirtimeRate > 0 ? String(format: "%.2f%%", result.averageAirtimeRate) : "—", x: col3)
				y += 26

				// Per-preset AI summary
				if !result.aiSummaryText.isEmpty {
					let aiAttrs: [NSAttributedString.Key: Any] = [.font: captionFont, .foregroundColor: darkGray]
					drawText(result.aiSummaryText, x: margin + 4, attrs: aiAttrs, maxWidth: contentWidth - 8)
				}

				// Subtle divider between presets
				y += 2
				let divPath = UIBezierPath()
				divPath.move(to: CGPoint(x: margin + 4, y: y))
				divPath.addLine(to: CGPoint(x: pageWidth - margin - 4, y: y))
				lightGray.setStroke()
				divPath.lineWidth = 0.25
				divPath.stroke()
				y += 6
			}

			// MARK: RF Health

			let hasRFData = session.presetResults.contains {
				$0.numPacketsTx > 0 || $0.numPacketsRx > 0 || $0.packetSuccessRate > 0
			}

			if hasRFData {
				drawSectionHeading("RF Health")

				for result in session.presetResults where result.numPacketsTx > 0 || result.numPacketsRx > 0 {
					checkPage(needed: 80)

					let presetAttrs: [NSAttributedString.Key: Any] = [.font: presetTitleFont, .foregroundColor: black]
					NSAttributedString(string: result.presetName, attributes: presetAttrs).draw(at: CGPoint(x: margin + 4, y: y))
					y += 18

					let errorRate = result.numPacketsRx > 0
						? (Double(result.numPacketsRxBad) / Double(result.numPacketsRx)) * 100
						: 0.0

					let colWidth: CGFloat = contentWidth * 0.25
					let col1 = margin + 4
					let col2 = margin + colWidth
					let col3 = margin + colWidth * 2
					let col4 = margin + colWidth * 3

					drawStatPair("Ch Util", String(format: "%.1f%%", result.averageChannelUtilization), x: col1)
					drawStatPair("Airtime", String(format: "%.1f%%", result.averageAirtimeRate), x: col2)
					drawStatPair("Packets Tx", "\(result.numPacketsTx)", x: col3)
					drawStatPair("Packets Rx", "\(result.numPacketsRx)", x: col4)
					y += 26

					drawStatPair("Error Rate", String(format: "%.1f%%", errorRate), x: col1)
					drawStatPair("Relayed", "\(result.numTxRelay)", x: col2)
					drawStatPair("Relay Canceled", "\(result.numTxRelayCanceled)", x: col3)
					drawStatPair("Duplicates", "\(result.numRxDupe)", x: col4)
					y += 26

					// Footer row
					var footerParts: [String] = []
					if result.numTotalNodes > 0 {
						footerParts.append("\(result.numOnlineNodes)/\(result.numTotalNodes) nodes online")
					}
					if result.uptimeSeconds > 0 {
						footerParts.append("Uptime: \(uptimeString(result.uptimeSeconds))")
					}
					if !footerParts.isEmpty {
						let footerAttrs: [NSAttributedString.Key: Any] = [.font: captionFont, .foregroundColor: medGray]
						drawText(footerParts.joined(separator: "  ·  "), x: margin + 4, attrs: footerAttrs)
					}

					y += 4
				}
			}

			// MARK: AI Recommendation

			let aiText = session.aiSummaryText
			if !aiText.isEmpty {
				drawSectionHeading("AI Recommendation")
				let aiBodyAttrs: [NSAttributedString.Key: Any] = [.font: bodyFont, .foregroundColor: darkGray]
				drawText(aiText, x: margin + 4, attrs: aiBodyAttrs, maxWidth: contentWidth - 8)
			}

			// MARK: Footer

			let genAttrs: [NSAttributedString.Key: Any] = [.font: captionFont, .foregroundColor: medGray]
			y += 8
			drawText("Generated by Meshtastic iOS · \(Date().formatted(date: .abbreviated, time: .shortened))", attrs: genAttrs)

			drawPageFooter()
		}
	}

	// MARK: - Map Snapshot

	private static func snapshotMap(session: DiscoverySessionEntity) async -> UIImage? {
		let nodesWithPosition = session.discoveredNodes.filter { $0.latitude != 0 && $0.longitude != 0 }
		let userCoord = CLLocationCoordinate2D(latitude: session.userLatitude, longitude: session.userLongitude)
		let hasUserPos = session.userLatitude != 0 && session.userLongitude != 0

		guard hasUserPos || !nodesWithPosition.isEmpty else { return nil }

		// Build coordinate set for region fitting
		var allCoords: [CLLocationCoordinate2D] = []
		if hasUserPos { allCoords.append(userCoord) }
		for node in nodesWithPosition {
			allCoords.append(CLLocationCoordinate2D(latitude: node.latitude, longitude: node.longitude))
		}

		// Calculate bounding region with padding
		var minLat = allCoords.map(\.latitude).min()!
		var maxLat = allCoords.map(\.latitude).max()!
		var minLon = allCoords.map(\.longitude).min()!
		var maxLon = allCoords.map(\.longitude).max()!

		let latSpan = max((maxLat - minLat) * 1.6, 0.005)
		let lonSpan = max((maxLon - minLon) * 1.6, 0.005)
		let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
		let region = MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lonSpan))

		let options = MKMapSnapshotter.Options()
		options.region = region
		options.size = CGSize(width: 1032, height: 560) // 2x for retina clarity in PDF
		options.mapType = .mutedStandard

		do {
			let snapshot = try await MKMapSnapshotter(options: options).start()
			let image = snapshot.image

			// Draw annotations on top
			UIGraphicsBeginImageContextWithOptions(image.size, true, image.scale)
			image.draw(at: .zero)

			// Node pins
			let nodeColor = UIColor(red: 0.36, green: 0.68, blue: 0.36, alpha: 1)
			for node in nodesWithPosition {
				let coord = CLLocationCoordinate2D(latitude: node.latitude, longitude: node.longitude)
				let point = snapshot.point(for: coord)
				let pinRect = CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12)
				nodeColor.setFill()
				UIBezierPath(ovalIn: pinRect).fill()
				UIColor.white.setStroke()
				let stroke = UIBezierPath(ovalIn: pinRect)
				stroke.lineWidth = 1.5
				stroke.stroke()
			}

			// User pin (orange, larger)
			if hasUserPos {
				let userPt = snapshot.point(for: userCoord)
				let userRect = CGRect(x: userPt.x - 8, y: userPt.y - 8, width: 16, height: 16)
				UIColor.systemOrange.setFill()
				UIBezierPath(ovalIn: userRect).fill()
				UIColor.white.setStroke()
				let stroke = UIBezierPath(ovalIn: userRect)
				stroke.lineWidth = 2
				stroke.stroke()
			}

			let annotatedImage = UIGraphicsGetImageFromCurrentImageContext()
			UIGraphicsEndImageContext()
			return annotatedImage
		} catch {
			Logger.services.error("Map snapshot for PDF failed: \(error.localizedDescription, privacy: .public)")
			return nil
		}
	}

	// MARK: - Helpers

	private static func formatDistance(_ meters: Double) -> String {
		let measurement = Measurement(value: meters, unit: UnitLength.meters)
		let formatter = MeasurementFormatter()
		formatter.unitOptions = .naturalScale
		formatter.numberFormatter.maximumFractionDigits = 1
		return formatter.string(from: measurement)
	}

	private static func uptimeString(_ seconds: Int) -> String {
		if seconds >= 3600 {
			return "\(seconds / 3600)h \((seconds % 3600) / 60)m"
		}
		return "\(seconds / 60)m \(seconds % 60)s"
	}
}
