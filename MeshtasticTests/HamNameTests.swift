import XCTest
@testable import Meshtastic

final class HamNameTests: XCTestCase {
	func testComposeJoinsCallSignAndLongNameWithHamSeparator() {
		let name = HamName(callSign: "KD2ABC", longName: "Attic Heltec")

		XCTAssertEqual(name.composed, "KD2ABC//Attic Heltec")
	}

	func testSplitRecoversCallSignAndLongNameFromFirmwareName() {
		let name = HamName(composed: "KD2ABC//Attic Heltec")

		XCTAssertEqual(name.callSign, "KD2ABC")
		XCTAssertEqual(name.longName, "Attic Heltec")
	}

	func testSplitTreatsBareFirmwareNameAsCallSign() {
		let name = HamName(composed: "KD2ABC")

		XCTAssertEqual(name.callSign, "KD2ABC")
		XCTAssertEqual(name.longName, "")
	}

	func testComposePreservesHamSeparatorWhenCallSignIsEmpty() {
		let name = HamName(callSign: "", longName: "Attic Heltec")

		XCTAssertEqual(name.composed, "//Attic Heltec")
	}

	func testCallSignIsLimitedToSevenUTF8Bytes() {
		XCTAssertEqual(HamName.limitCallSign("KD2ABCDE"), "KD2ABCD")
	}

	func testLongNameIsLimitedToFourteenUTF8BytesWithoutBreakingCharacters() {
		XCTAssertEqual(HamName.limitLongName("Attic 🛰 Heltec"), "Attic 🛰 Hel")
	}

	func testOnboardingMovesAnExistingLongNameToTheOptionalHamName() {
		XCTAssertEqual(HamName.forOnboarding("Attic Heltec"), "//Attic Heltec")
	}

	func testUnlicensingFlattensAnIncompleteHamName() {
		XCTAssertEqual(HamName.forUnlicensing("//Attic Heltec"), "Attic Heltec")
	}
}
