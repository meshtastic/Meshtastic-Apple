//
//  TerminalScreen.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/8/26.
//

import Foundation

/// A terminal color as the remote program asked for it. The view maps it to a color that
/// reads on the current theme.
enum TerminalColor: Equatable, Hashable {
	/// One of the 16 standard colors, 0-7 normal and 8-15 bright.
	case ansi(UInt8)
	/// An entry of the 256 color palette above the first 16.
	case indexed(UInt8)
	case rgb(UInt8, UInt8, UInt8)
}

struct TerminalStyle: Equatable, Hashable {
	var foreground: TerminalColor?
	var background: TerminalColor?
	var bold = false
	var dim = false
	var italic = false
	var underline = false
	var inverse = false

	static let plain = TerminalStyle()
}

/// A run of characters in one style.
struct TerminalRun: Equatable {
	var text: String
	var style: TerminalStyle
}

/// The remote shell's output as lines of styled text.
///
/// It handles what a line oriented shell sends: printable text, carriage return overwrite,
/// backspace, tabs, SGR color and attributes, erase in line, clear, and cursor moves along
/// the current line. Moves between rows are ignored. Full screen programs (`vi`, `top`)
/// switch to the alternate screen, which can't be drawn this way; `fullScreenRequested` is
/// set so the view can say why.
struct TerminalScreen {
	struct Cell: Equatable {
		var character: Character
		var style: TerminalStyle
	}

	/// Lines kept for scrolling back.
	static let maxLines = 2_000
	/// How far a control sequence can move the cursor or widen a line, so a bad count from
	/// the remote side can't grow a line without limit.
	static let maxColumns = 1_000

	private(set) var lines: [[Cell]] = [[]]
	/// Column of the cursor on the last line.
	private(set) var cursorColumn = 0
	private(set) var style = TerminalStyle.plain
	/// Set when the remote program tries to take over the whole screen.
	private(set) var fullScreenRequested = false
	/// Counts bells, so the view can tell a new one from one it already played.
	private(set) var bellCount = 0
	/// Set by the remote program (DECCKM) when arrow keys should send `ESC O` sequences.
	private(set) var applicationCursorKeys = false
	/// Bumped whenever the text changes, so views can skip redrawing an unchanged screen.
	private(set) var revision = 0

	private var parser = Parser.ground
	private var utf8 = UTF8Decoder()

	/// The text of the line the cursor is on.
	var currentLineText: String {
		String(lines[lines.count - 1].map(\.character))
	}

	mutating func clear() {
		lines = [[]]
		cursorColumn = 0
		revision &+= 1
	}

	/// Clears the full screen notice once the person has seen it.
	mutating func acknowledgeFullScreen() {
		fullScreenRequested = false
	}

	mutating func feed(_ data: Data) {
		for byte in data {
			feed(byte: byte)
		}
		revision &+= 1
	}

	// MARK: - Parsing

	private enum Parser {
		case ground
		case escape
		/// A control sequence: private marker (`?`, `>`), parameters so far.
		case csi(marker: UInt8?, parameters: [UInt8])
		/// An operating system command, such as a window title. Skipped to its terminator.
		case osc(sawEscape: Bool)
		/// A character set selection (`ESC ( B`): one more byte to skip.
		case charset
	}

	private mutating func feed(byte: UInt8) {
		switch parser {
		case .ground:
			ground(byte)
		case .escape:
			escape(byte)
		case let .csi(marker, parameters):
			switch byte {
			case 0x30...0x3B:
				parser = .csi(marker: marker, parameters: parameters + [byte])
			case 0x3C...0x3F where parameters.isEmpty && marker == nil:
				parser = .csi(marker: byte, parameters: parameters)
			case 0x20...0x2F, 0x3C...0x3F:
				parser = .csi(marker: marker, parameters: parameters)
			case 0x40...0x7E:
				parser = .ground
				controlSequence(final: byte, marker: marker, parameters: Self.numbers(parameters))
			case 0x18, 0x1A:
				parser = .ground
			case 0x1B:
				parser = .escape
			default:
				// C0 controls inside a sequence act immediately.
				ground(byte)
			}
		case let .osc(sawEscape):
			if byte == 0x07 || (sawEscape && byte == 0x5C) {
				parser = .ground
			} else {
				parser = .osc(sawEscape: byte == 0x1B)
			}
		case .charset:
			parser = .ground
		}
	}

	private mutating func ground(_ byte: UInt8) {
		switch byte {
		case 0x1B:
			utf8.reset()
			parser = .escape
		case 0x07:
			bellCount &+= 1
		case 0x08:
			cursorColumn = max(0, cursorColumn - 1)
		case 0x09:
			let next = (cursorColumn / 8 + 1) * 8
			while cursorColumn < next { put(" ") }
		case 0x0A, 0x0B, 0x0C:
			newLine()
		case 0x0D:
			cursorColumn = 0
		case 0x00...0x1F, 0x7F:
			break
		default:
			for character in utf8.decode(byte) {
				put(character)
			}
		}
	}

	private mutating func escape(_ byte: UInt8) {
		switch byte {
		case 0x5B: // [
			parser = .csi(marker: nil, parameters: [])
		case 0x5D: // ]
			parser = .osc(sawEscape: false)
		case 0x28, 0x29, 0x2A, 0x2B: // ( ) * +
			parser = .charset
		case 0x63: // c, full reset
			parser = .ground
			style = .plain
			clear()
		case 0x37, 0x38, 0x3D, 0x3E: // save/restore cursor, keypad modes
			parser = .ground
		default:
			parser = .ground
		}
	}

	private static func numbers(_ bytes: [UInt8]) -> [Int?] {
		guard !bytes.isEmpty else { return [] }
		return (String(bytes: bytes, encoding: .ascii) ?? "")
			.split(separator: ";", omittingEmptySubsequences: false)
			.map { Int($0.split(separator: ":").first ?? "") }
	}

	private mutating func controlSequence(final: UInt8, marker: UInt8?, parameters: [Int?]) {
		let first = parameters.first.flatMap { $0 }
		let count = min(max(first ?? 1, 1), Self.maxColumns)
		if marker == 0x3F { // ?
			let set = final == 0x68 // h; l resets
			guard set || final == 0x6C else { return }
			if parameters.contains(1) {
				applicationCursorKeys = set
			}
			// The alternate screen is the clearest sign of a full screen program.
			if set, parameters.contains(where: { [47, 1047, 1049].contains($0) }) {
				fullScreenRequested = true
			}
			return
		}
		guard marker == nil else { return }
		switch final {
		case 0x6D: // m
			selectGraphicRendition(parameters)
		case 0x4B: // K, erase in line
			eraseInLine(first ?? 0)
		case 0x4A: // J, erase in display
			switch first ?? 0 {
			case 2, 3:
				clear()
			case 0:
				eraseInLine(0)
			default:
				break
			}
		case 0x43: // C, cursor forward
			let target = min(cursorColumn + count, max(cursorColumn, Self.maxColumns))
			padLine(to: target)
			cursorColumn = target
		case 0x44: // D, cursor back
			cursorColumn = max(0, cursorColumn - count)
		case 0x47: // G, cursor to column
			let target = count - 1
			padLine(to: target)
			cursorColumn = target
		case 0x50: // P, delete characters
			deleteCharacters(count)
		case 0x40: // @, insert blanks
			insertBlanks(count)
		case 0x58: // X, erase characters
			eraseCharacters(count)
		case 0x48, 0x66: // H, f: cursor position; only the column applies on a single line
			let column = parameters.count > 1 ? (parameters[1] ?? 1) : 1
			let target = min(max(column - 1, 0), Self.maxColumns - 1)
			padLine(to: target)
			cursorColumn = target
		default:
			break
		}
	}

	private mutating func selectGraphicRendition(_ parameters: [Int?]) {
		var codes = parameters.map { $0 ?? 0 }
		if codes.isEmpty { codes = [0] }
		var index = 0
		while index < codes.count {
			let code = codes[index]
			switch code {
			case 0: style = .plain
			case 1: style.bold = true
			case 2: style.dim = true
			case 3: style.italic = true
			case 4: style.underline = true
			case 7: style.inverse = true
			case 21, 22: style.bold = false; style.dim = false
			case 23: style.italic = false
			case 24: style.underline = false
			case 27: style.inverse = false
			case 30...37: style.foreground = .ansi(UInt8(code - 30))
			case 39: style.foreground = nil
			case 40...47: style.background = .ansi(UInt8(code - 40))
			case 49: style.background = nil
			case 90...97: style.foreground = .ansi(UInt8(code - 90 + 8))
			case 100...107: style.background = .ansi(UInt8(code - 100 + 8))
			case 38, 48:
				var color: TerminalColor?
				if index + 2 < codes.count, codes[index + 1] == 5 {
					color = Self.paletteColor(codes[index + 2])
					index += 2
				} else if index + 4 < codes.count, codes[index + 1] == 2 {
					color = .rgb(Self.byte(codes[index + 2]), Self.byte(codes[index + 3]), Self.byte(codes[index + 4]))
					index += 4
				}
				if code == 38 { style.foreground = color } else { style.background = color }
			default:
				break
			}
			index += 1
		}
	}

	private static func byte(_ value: Int) -> UInt8 {
		UInt8(clamping: value)
	}

	private static func paletteColor(_ value: Int) -> TerminalColor {
		let index = byte(value)
		return index < 16 ? .ansi(index) : .indexed(index)
	}

	// MARK: - Editing the current line

	private mutating func put(_ character: Character) {
		let row = lines.count - 1
		let cell = Cell(character: character, style: style)
		if cursorColumn < lines[row].count {
			lines[row][cursorColumn] = cell
		} else {
			padLine(to: cursorColumn)
			lines[row].append(cell)
		}
		cursorColumn += 1
	}

	private mutating func padLine(to column: Int) {
		let row = lines.count - 1
		while lines[row].count < column {
			lines[row].append(Cell(character: " ", style: style))
		}
	}

	private mutating func newLine() {
		lines.append([])
		cursorColumn = 0
		if lines.count > Self.maxLines {
			lines.removeFirst(lines.count - Self.maxLines)
		}
	}

	private mutating func eraseInLine(_ mode: Int) {
		let row = lines.count - 1
		switch mode {
		case 0:
			if cursorColumn < lines[row].count {
				lines[row].removeSubrange(cursorColumn...)
			}
		case 1:
			for column in 0..<min(cursorColumn + 1, lines[row].count) {
				lines[row][column] = Cell(character: " ", style: style)
			}
		default:
			lines[row] = []
		}
	}

	private mutating func deleteCharacters(_ count: Int) {
		let row = lines.count - 1
		guard cursorColumn < lines[row].count else { return }
		let end = min(cursorColumn + count, lines[row].count)
		lines[row].removeSubrange(cursorColumn..<end)
	}

	private mutating func insertBlanks(_ count: Int) {
		let row = lines.count - 1
		guard cursorColumn < lines[row].count else { return }
		// Characters pushed past the right edge are dropped, as on a real terminal.
		let width = max(lines[row].count, Self.maxColumns)
		lines[row].insert(contentsOf: Array(repeating: Cell(character: " ", style: style), count: count), at: cursorColumn)
		if lines[row].count > width {
			lines[row].removeLast(lines[row].count - width)
		}
	}

	private mutating func eraseCharacters(_ count: Int) {
		let row = lines.count - 1
		for column in cursorColumn..<min(cursorColumn + count, lines[row].count) {
			lines[row][column] = Cell(character: " ", style: style)
		}
	}

	// MARK: - Runs

	/// A line as runs of one style, for drawing.
	static func runs(_ line: [Cell]) -> [TerminalRun] {
		var runs: [TerminalRun] = []
		for cell in line {
			if let last = runs.last, last.style == cell.style {
				runs[runs.count - 1].text.append(cell.character)
			} else {
				runs.append(TerminalRun(text: String(cell.character), style: cell.style))
			}
		}
		return runs
	}
}

/// Decodes UTF-8 one byte at a time, since output frames can split a character.
struct UTF8Decoder {
	private var pending: [UInt8] = []
	private var expected = 0

	mutating func reset() {
		pending = []
		expected = 0
	}

	/// The characters this byte completes: none mid-sequence, two when it ends a broken
	/// sequence and is itself a character.
	mutating func decode(_ byte: UInt8) -> [Character] {
		if pending.isEmpty {
			switch byte {
			case 0x00...0x7F:
				return [Character(Unicode.Scalar(byte))]
			case 0xC0...0xDF: expected = 2
			case 0xE0...0xEF: expected = 3
			case 0xF0...0xF7: expected = 4
			default:
				return ["\u{FFFD}"]
			}
			pending = [byte]
			return []
		}
		guard byte & 0xC0 == 0x80 else {
			// A broken sequence: drop it and start over with this byte.
			reset()
			return ["\u{FFFD}"] + decode(byte)
		}
		pending.append(byte)
		guard pending.count == expected else { return [] }
		defer { reset() }
		return [String(bytes: pending, encoding: .utf8)?.first ?? "\u{FFFD}"]
	}
}
