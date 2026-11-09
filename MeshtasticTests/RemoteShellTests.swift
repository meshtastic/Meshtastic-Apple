//
//  RemoteShellTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 11/8/26.
//

import Foundation
import MeshtasticProtobufs
import Testing
import UIKit
@testable import Meshtastic

@Suite("Terminal screen")
struct TerminalScreenTests {

	private func screen(_ text: String) -> TerminalScreen {
		var screen = TerminalScreen()
		screen.feed(Data(text.utf8))
		return screen
	}

	private func text(_ screen: TerminalScreen) -> [String] {
		screen.lines.map { String($0.map(\.character)) }
	}

	@Test func linesAndCarriageReturnOverwrite() {
		let result = screen("one\r\n 10%\r 55%\r100%")
		#expect(text(result) == ["one", "100%"])
	}

	@Test func backspaceAndEraseInLine() {
		#expect(text(screen("abc\u{8}\u{8}\u{1B}[K")) == ["a"])
		#expect(text(screen("hello\r\u{1B}[2K")) == [""])
	}

	@Test func clearScreen() {
		#expect(text(screen("a\r\nb\u{1B}[2J")) == [""])
	}

	@Test func sixteenColorsAndAttributes() {
		let result = screen("\u{1B}[1;31mred\u{1B}[0m \u{1B}[4;7mx")
		let runs = TerminalScreen.runs(result.lines[0])
		#expect(runs.count == 3)
		#expect(runs[0].style.foreground == .ansi(1))
		#expect(runs[0].style.bold)
		#expect(runs[1].style == .plain)
		#expect(runs[2].style.underline && runs[2].style.inverse)
	}

	@Test func paletteAndTruecolor() {
		let result = screen("\u{1B}[38;5;208ma\u{1B}[48;2;10;20;30mb\u{1B}[38;5;9mc")
		let cells = result.lines[0]
		#expect(cells[0].style.foreground == .indexed(208))
		#expect(cells[1].style.background == .rgb(10, 20, 30))
		#expect(cells[2].style.foreground == .ansi(9))
	}

	@Test func utf8SplitAcrossFrames() {
		var screen = TerminalScreen()
		let bytes = Array("é✓".utf8)
		screen.feed(Data(bytes.prefix(3)))
		screen.feed(Data(bytes.dropFirst(3)))
		#expect(text(screen) == ["é✓"])
	}

	@Test func brokenUTF8KeepsTheByteThatBrokeIt() {
		var screen = TerminalScreen()
		screen.feed(Data([0xC3, 0x41]))
		#expect(text(screen) == ["\u{FFFD}A"])
		screen.feed(Data([0xC3, 0xE2, 0x9C, 0x93]))
		#expect(text(screen) == ["\u{FFFD}A\u{FFFD}✓"])
	}

	@Test func controlSequenceCountsAreBounded() {
		#expect(screen("\u{1B}[100000000C").lines[0].count == TerminalScreen.maxColumns)
		#expect(screen("ab\u{1B}[9223372036854775807C").lines[0].count == TerminalScreen.maxColumns)
		#expect(screen("\u{1B}[100000000G").lines[0].count == TerminalScreen.maxColumns - 1)
		let inserted = screen("abc\u{1B}[1G\u{1B}[100000000@")
		#expect(inserted.lines[0].count == TerminalScreen.maxColumns)
		#expect(text(screen("abc\u{1B}[1G\u{1B}[9223372036854775807P")) == [""])
		#expect(text(screen("abc\u{1B}[2G\u{1B}[9223372036854775807X")) == ["a  "])
	}

	@Test func alternateScreenIsAFullScreenProgram() {
		#expect(screen("\u{1B}[?1049h").fullScreenRequested)
		#expect(!screen("\u{1B}[?2004h$ ").fullScreenRequested)
	}

	@Test func cursorKeyModeAndTitlesAreConsumed() {
		let result = screen("\u{1B}]0;user@host\u{7}\u{1B}[?1h$ ")
		#expect(text(result) == ["$ "])
		#expect(result.applicationCursorKeys)
		#expect(result.bellCount == 0)
	}

	@Test func bell() {
		#expect(screen("\u{7}").bellCount == 1)
	}
}

@Suite("Local echo")
struct LocalEchoTests {

	private func typed(_ echo: inout LocalEcho, _ text: String) {
		for character in text { echo.typed(character) }
		echo.markSent(now: .now)
	}

	@Test func nothingDrawnUntilTheLineEchoes() {
		var echo = LocalEcho()
		typed(&echo, "ls")
		#expect(echo.visible(atSecretPrompt: false).sent.isEmpty)
		echo.received(Data("l".utf8))
		#expect(echo.visible(atSecretPrompt: false).sent == "s")
		echo.received(Data("s".utf8))
		#expect(echo.visible(atSecretPrompt: false).sent.isEmpty)
		typed(&echo, " -l")
		#expect(echo.visible(atSecretPrompt: false).sent == " -l")
	}

	@Test func divergentEchoDropsPredictions() {
		var echo = LocalEcho()
		typed(&echo, "ab")
		echo.received(Data("a".utf8))
		echo.received(Data("x".utf8))
		#expect(echo.predictions.isEmpty)
		#expect(!echo.confirmedOnLine)
	}

	@Test func nonEchoingPromptNeverDraws() {
		var echo = LocalEcho()
		typed(&echo, "hunter2")
		echo.received(Data("\r\n".utf8))
		#expect(echo.visible(atSecretPrompt: false).sent.isEmpty)
	}

	@Test func secretPromptDrawsNothing() {
		var echo = LocalEcho()
		typed(&echo, "ab")
		echo.received(Data("a".utf8))
		#expect(echo.visible(atSecretPrompt: true).sent.isEmpty)
	}

	@Test("Secret prompts", arguments: [
		"[sudo] password for pi: ", "Password:", "Enter passphrase for key '/root/.ssh/id_ed25519': ", "PIN: "
	])
	func secretPrompts(_ line: String) {
		#expect(LocalEcho.isSecretPrompt(line))
	}

	@Test("Ordinary prompts", arguments: ["pi@host:~ $ ", "Pinging host:", "Change password? [y/N] "])
	func ordinaryPrompts(_ line: String) {
		#expect(!LocalEcho.isSecretPrompt(line))
	}

	@Test func timedOutPredictionTurnsPredictionOffUntilEnter() {
		var echo = LocalEcho()
		typed(&echo, "ab")
		echo.received(Data("a".utf8))
		echo.expire(now: .now.addingTimeInterval(30), roundTrip: 1)
		#expect(echo.disabledUntilEnter)
		echo.enter()
		#expect(!echo.disabledUntilEnter)
	}
}

@Suite("Remote shell link")
struct RemoteShellLinkTests {

	private let start = Date(timeIntervalSince1970: 1_000)

	private func frame(_ op: RemoteShell.OpCode, seq: UInt32, ack: UInt32 = 0, payload: String = "", session: UInt32 = 7) -> RemoteShell {
		var frame = RemoteShell()
		frame.op = op
		frame.sessionID = session
		frame.seq = seq
		frame.ackSeq = ack
		frame.payload = Data(payload.utf8)
		return frame
	}

	private func openLink() -> RemoteShellLink {
		var link = RemoteShellLink(sessionId: 7)
		link.open(cols: 80, rows: 24, now: start)
		link.receive(frame(.openOk, seq: 1, ack: 1), now: start.addingTimeInterval(0.5))
		link.outbox = []
		link.events = []
		return link
	}

	@Test func openCarriesSizeAndRetriesThenGivesUp() {
		var link = RemoteShellLink(sessionId: 7)
		link.open(cols: 100, rows: 30, now: start)
		#expect(link.outbox.count == 1)
		#expect(link.outbox[0].op == .open && link.outbox[0].seq == 1 && link.outbox[0].cols == 100 && link.outbox[0].rows == 30)
		link.outbox = []
		link.tick(now: start.addingTimeInterval(5))
		#expect(link.outbox.map(\.seq) == [1])
		link.tick(now: start.addingTimeInterval(61))
		#expect(link.events.last == .failed(.noReply))
		#expect(link.outbox.last?.op == .close)
		#expect(link.phase == .closed)
	}

	@Test func openOkOpensAndMeasuresRoundTrip() {
		let link = openLink()
		#expect(link.phase == .open)
		#expect(link.roundTrip == 0.5)
	}

	@Test func retriedOpenTakesNoRoundTripSample() {
		var link = RemoteShellLink(sessionId: 7)
		link.open(cols: 80, rows: 24, now: start)
		link.tick(now: start.addingTimeInterval(5))
		link.receive(frame(.openOk, seq: 1, ack: 1), now: start.addingTimeInterval(16))
		#expect(link.phase == .open)
		#expect(link.roundTrip == nil)
	}

	@Test func inputIsSequencedAndCarriesTheReceiveCursor() {
		var link = openLink()
		link.send(Data("ls\r".utf8), now: start.addingTimeInterval(1))
		#expect(link.outbox.count == 1)
		#expect(link.outbox[0].op == .input && link.outbox[0].seq == 2 && link.outbox[0].ackSeq == 1)
		#expect(link.outbox[0].payload == Data("ls\r".utf8))
	}

	@Test func windowHoldsInputAndFullWindowRetransmits() {
		var link = openLink()
		for index in 0..<6 {
			link.send(Data([UInt8(0x61 + index)]), now: start.addingTimeInterval(1))
		}
		// OPEN was acknowledged, so four INPUT frames fit; the rest coalesce until room opens.
		#expect(link.outbox.map(\.seq) == [2, 3, 4, 5])
		link.outbox = []
		link.tick(now: start.addingTimeInterval(1.5))
		#expect(link.outbox.isEmpty)
		link.tick(now: start.addingTimeInterval(2.1))
		#expect(link.outbox.map(\.seq) == [2])
		#expect(link.oldestUnackedAge(now: start.addingTimeInterval(5)) == 4)

		link.outbox = []
		link.receive(frame(.output, seq: 2, ack: 5, payload: "abcd"), now: start.addingTimeInterval(3))
		#expect(link.outbox.map(\.seq) == [6])
		#expect(link.outbox[0].payload == Data("ef".utf8))
	}

	@Test func outOfOrderOutputIsHeldAndAGapRequested() {
		var link = openLink()
		link.receive(frame(.output, seq: 3, payload: "b"), now: start.addingTimeInterval(1))
		#expect(link.events.isEmpty)
		let request = link.outbox.last
		#expect(request?.op == .ack && request?.seq == 0 && request?.lastRxSeq == 1)
		link.receive(frame(.output, seq: 2, payload: "a"), now: start.addingTimeInterval(1.2))
		#expect(link.events == [.output(Data("a".utf8)), .output(Data("b".utf8))])
	}

	@Test func duplicatesAreAcknowledgedNotRepeated() {
		var link = openLink()
		link.receive(frame(.output, seq: 2, payload: "a"), now: start.addingTimeInterval(1))
		link.events = []
		link.outbox = []
		link.receive(frame(.output, seq: 2, payload: "a"), now: start.addingTimeInterval(1.1))
		#expect(link.events.isEmpty)
		#expect(link.outbox.count == 1 && link.outbox[0].op == .ack && link.outbox[0].lastRxSeq == 0 && link.outbox[0].ackSeq == 2)
	}

	@Test func bareAckEveryTwoFrames() {
		var link = openLink()
		// OPEN_OK and this frame make two since anything went out.
		link.receive(frame(.output, seq: 2, payload: "a"), now: start.addingTimeInterval(1))
		#expect(link.outbox.count == 1 && link.outbox[0].op == .ack && link.outbox[0].ackSeq == 2)
		link.outbox = []
		link.receive(frame(.output, seq: 3, payload: "b"), now: start.addingTimeInterval(1))
		#expect(link.outbox.isEmpty)
		link.receive(frame(.output, seq: 4, payload: "c"), now: start.addingTimeInterval(1))
		#expect(link.outbox.count == 1 && link.outbox[0].op == .ack && link.outbox[0].ackSeq == 4)
	}

	@Test func replayRequestResendsFromTheNextFrame() {
		var link = openLink()
		link.send(Data("a".utf8), now: start.addingTimeInterval(1))
		link.send(Data("b".utf8), now: start.addingTimeInterval(1))
		link.outbox = []
		var request = frame(.ack, seq: 0, ack: 2)
		request.lastRxSeq = 2
		link.receive(request, now: start.addingTimeInterval(2))
		#expect(link.outbox.map(\.seq) == [3])
	}

	@Test func closedAndSessionlessErrorsEndTheSession() {
		var link = openLink()
		link.receive(frame(.closed, seq: 9, payload: "shell_exited"), now: start.addingTimeInterval(1))
		#expect(link.events == [.closed(reason: "shell_exited")])
		#expect(link.phase == .closed)

		var refused = RemoteShellLink(sessionId: 7)
		refused.open(cols: 80, rows: 24, now: start)
		refused.receive(frame(.error, seq: 0, payload: "invalid_session"), now: start.addingTimeInterval(1))
		#expect(refused.events == [.failed(.refused("invalid_session"))])
	}

	@Test func framesForOtherSessionsAreIgnored() {
		var link = openLink()
		link.receive(frame(.output, seq: 2, payload: "x", session: 8), now: start.addingTimeInterval(1))
		#expect(link.events.isEmpty)
	}

	@Test func pingAfterSilence() {
		var link = openLink()
		link.tick(now: start.addingTimeInterval(4))
		#expect(link.outbox.isEmpty)
		link.tick(now: start.addingTimeInterval(6))
		#expect(link.outbox.count == 1 && link.outbox[0].op == .ping && link.outbox[0].seq == 2)
	}

	@Test func resizeIsSequenced() {
		var link = openLink()
		link.resize(cols: 60, rows: 20, now: start.addingTimeInterval(1))
		#expect(link.outbox.count == 1 && link.outbox[0].op == .resize && link.outbox[0].cols == 60 && link.outbox[0].rows == 20)
	}

	@Test func inputBeyondTheQueueIsDropped() {
		var link = RemoteShellLink(sessionId: 7)
		link.open(cols: 80, rows: 24, now: start)
		link.send(Data(count: RemoteShellLink.maxQueuedInput + 10), now: start)
		#expect(link.events == [.inputDropped(10)])
	}
}

@Suite("Remote shell keys")
struct RemoteShellKeyTests {

	@Test func controlChords() {
		#expect(RemoteShellSession.chordBytes("c", control: true, alt: false) == [0x03])
		#expect(RemoteShellSession.chordBytes("[", control: true, alt: false) == [0x1B])
		#expect(RemoteShellSession.chordBytes(" ", control: true, alt: false) == [0x00])
		#expect(RemoteShellSession.chordBytes("?", control: true, alt: false) == [0x7F])
		#expect(RemoteShellSession.chordBytes("b", control: false, alt: true) == [0x1B, 0x62])
	}

	@Test func navigationKeys() {
		#expect(TerminalKey.up.bytes(applicationCursor: false) == [0x1B, 0x5B, 0x41])
		#expect(TerminalKey.up.bytes(applicationCursor: true) == [0x1B, 0x4F, 0x41])
		#expect(TerminalKey.pageDown.bytes(applicationCursor: false) == Array("\u{1B}[6~".utf8))
	}

	@Test func stickyModifierCycles() {
		#expect(StickyModifier.off.next == .once)
		#expect(StickyModifier.once.next == .locked)
		#expect(StickyModifier.locked.next == .off)
	}

	@Test("Every standard color reads on both themes", arguments: [false, true])
	func paletteContrast(dark: Bool) {
		let background: UIColor = dark ? .black : .white
		let text: UIColor = dark ? .white : .black
		for index in 0..<16 {
			let color = TerminalPalette.legible(TerminalPalette.color(.ansi(UInt8(index)), dark: dark), on: background, text: text)
			#expect(TerminalPalette.contrast(color, background) >= TerminalPalette.minimumContrast)
		}
	}
}

@Suite("Terminal palette")
struct TerminalPaletteTests {

	private let backgrounds: [(String, UIColor)] = [("light", .white), ("dark", .black)]

	@Test("Dim text keeps 4.5:1 for every standard color on both themes")
	func dimKeepsContrast() {
		for (name, background) in backgrounds {
			let isDark = name == "dark"
			for index in UInt8(0)..<16 {
				let color = TerminalPalette.color(.ansi(index), dark: isDark)
				let legible = TerminalPalette.legible(color, on: background, text: isDark ? .white : .black)
				let dimmed = TerminalPalette.dimmed(legible, on: background)
				#expect(TerminalPalette.contrast(dimmed, background) >= TerminalPalette.minimumContrast, "\(name) \(index)")
			}
		}
	}

	@Test("White text on a mid-gray background still reaches 4.5:1, dimmed or not")
	func midGrayBackground() {
		let gray = UIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
		let legible = TerminalPalette.legible(.white, on: gray, text: .white)
		#expect(TerminalPalette.contrast(legible, gray) >= TerminalPalette.minimumContrast)
		let dimmed = TerminalPalette.dimmed(legible, on: gray)
		#expect(TerminalPalette.contrast(dimmed, gray) >= TerminalPalette.minimumContrast)
	}

	@Test("Dim text with room to spare is visibly dimmer")
	func dimFadesWhenItCan() {
		let dimmed = TerminalPalette.dimmed(.black, on: .white)
		#expect(TerminalPalette.contrast(dimmed, .white) < TerminalPalette.contrast(.black, .white))
		#expect(TerminalPalette.contrast(dimmed, .white) >= TerminalPalette.minimumContrast)
	}
}
