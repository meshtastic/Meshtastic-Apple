//
//  ChannelLabelRenderer.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/26/26.
//

import CoreGraphics
import Foundation
import MeshtasticProtobufs

/// What a channel label shows: the Share Channels QR and enough to say what scanning it does.
struct ChannelLabelContent {
	var url: String
	/// The first channel's name, or the preset's when the channel has none (LongFast).
	var title: String
	/// Region and preset, e.g. "US · LongFast".
	var radio: String
	var channelCount: Int
	var replaces: Bool

	init(url: String, channelSet: ChannelSet, replaces: Bool) {
		self.url = url
		let preset = ModemPresets(rawValue: Int(channelSet.loraConfig.modemPreset.rawValue))?.name ?? ""
		let region = RegionCodes(rawValue: Int(channelSet.loraConfig.region.rawValue))?.topic ?? ""
		let firstName = channelSet.settings.first?.name ?? ""
		title = firstName.isEmpty ? (preset.isEmpty ? "Meshtastic" : preset) : firstName
		// The preset's default channel is named after it, so say what it is instead of
		// repeating the name.
		let detail = firstName.isEmpty ? String(localized: "Default channel") : (channelSet.loraConfig.usePreset ? preset : "")
		radio = [region, detail].filter { !$0.isEmpty }.joined(separator: " · ")
		channelCount = channelSet.settings.count
		self.replaces = replaces
	}
}

/// A channel QR label for 12 mm die-cut stock, laid out like the name tag: QR left, a JOIN MY
/// MESH band from 40 mm up, the channel's name big, region and preset under it, and on the
/// bottom row what scanning does, beside the mark.
enum ChannelLabelRenderer {
	private static let endPx = 3
	private static let edgePx = 2
	private static let narrowPx = 180
	private static let bandPx = 22
	private static let markPx = 18

	enum Failure: LocalizedError {
		case qrTooBig
		var errorDescription: String? {
			String(localized: "These channels make a QR too dense for a 12 mm label. Share fewer channels to print one.")
		}
	}

	static func image(for content: ChannelLabelContent, lengthDots length: Int) throws -> CGImage? {
		let across = NameTagRenderer.headDots
		guard let modules = NameTagRenderer.qrMatrix(content.url) else { return nil }
		// 2 dots per module is the smallest that scans off thermal paper; channel links have
		// nothing to trim, so a code that doesn't fit isn't printed.
		guard (modules.count + 2) * 2 <= across else { throw Failure.qrTooBig }
		// The largest whole number of dots per module that fits, as labeltastic picks it.
		let module = across / (modules.count + 2)
		guard let canvas = NameTagCanvas(width: length, height: across) else { return nil }
		let e = edgePx

		let side = modules.count * module
		let qrTop = (across - side) / 2
		for (row, line) in modules.enumerated() {
			for (column, ink) in line.enumerated() where ink {
				canvas.fill(x: endPx + module + column * module, y: qrTop + row * module, width: module, height: module, gray: 0)
			}
		}
		let x = endPx + side + 2 * module + 6
		let width = length - x - endPx
		let narrow = width < narrowPx

		let top: Int
		if narrow {
			top = e
		} else {
			canvas.band(in: CGRect(x: x, y: e, width: width, height: bandPx), text: String(localized: "JOIN MY MESH"), size: 21)
			top = e + bandPx
		}
		let markWidth = canvas.drawMark(height: markPx, right: length - endPx, bottom: across - e)

		let title = NameTagCanvas.clean(content.title)
		let idY = across - e - 9
		let (bigText, bigSize) = canvas.fit(title, maxWidth: width, size: narrow ? 34 : 30)
		let (radioText, radioSize) = canvas.fit(content.radio, maxWidth: width, size: narrow ? 18 : 16)
		// Name and radio as one block, centred above the bottom row.
		let block = bigSize + 4 + radioSize
		let blockTop = top + (idY - 9 - top - block) / 2
		canvas.draw(bigText, x: x, yCenter: blockTop + bigSize / 2, size: bigSize)
		canvas.draw(radioText, x: x, yCenter: blockTop + bigSize + 4 + radioSize / 2, size: radioSize)

		let action: String
		if content.replaces {
			action = String(localized: "Replaces channels")
		} else if content.channelCount == 1 {
			action = String(localized: "Adds 1 channel")
		} else {
			action = String(localized: "Adds \(content.channelCount) channels")
		}
		let (actionText, actionSize) = canvas.fit(action, maxWidth: width - markWidth - 6, size: 14)
		canvas.draw(actionText, x: x, yCenter: idY, size: actionSize)
		return canvas.image()
	}
}
