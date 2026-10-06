//
//  OutgoingMessageTextTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/5/26.
//
import Testing
@testable import Meshtastic

@Suite("Outgoing message text")
struct OutgoingMessageTextTests {

	@Test func strayReturnsAndSpacesAroundTheMessageAreDropped() {
		#expect(AccessoryManager.outgoingMessageText("hello\n\n") == "hello")
		#expect(AccessoryManager.outgoingMessageText("\n  hello \r\n") == "hello")
	}

	@Test func lineBreaksInsideTheMessageAreKept() {
		#expect(AccessoryManager.outgoingMessageText("line one\nline two\n") == "line one\nline two")
	}

	@Test func aMessageOfOnlyWhitespaceBecomesEmpty() {
		#expect(AccessoryManager.outgoingMessageText(" \n\t\n").isEmpty)
	}
}
