import Testing
@testable import Meshtastic

@Suite("Ham name")
struct HamNameTests {
	@Test func composeJoinsCallSignAndLongNameWithHamSeparator() {
		let name = HamName(callSign: "KD2ABC", longName: "Attic Heltec")

		#expect(name.composed == "KD2ABC//Attic Heltec")
	}

	@Test func splitRecoversCallSignAndLongNameFromFirmwareName() {
		let name = HamName(composed: "KD2ABC//Attic Heltec")

		#expect(name.callSign == "KD2ABC")
		#expect(name.longName == "Attic Heltec")
	}

	@Test func splitTreatsBareFirmwareNameAsCallSign() {
		let name = HamName(composed: "KD2ABC")

		#expect(name.callSign == "KD2ABC")
		#expect(name.longName == "")
	}

	@Test func composePreservesHamSeparatorWhenCallSignIsEmpty() {
		let name = HamName(callSign: "", longName: "Attic Heltec")

		#expect(name.composed == "//Attic Heltec")
	}

	@Test func callSignIsLimitedToSevenUTF8Bytes() {
		#expect(HamName.limitCallSign("KD2ABCDE") == "KD2ABCD")
	}

	@Test func longNameIsLimitedToFourteenUTF8BytesWithoutBreakingCharacters() {
		#expect(HamName.limitLongName("Attic 🛰 Heltec") == "Attic 🛰 Hel")
	}

	@Test func onboardingMovesAnExistingLongNameToTheOptionalHamName() {
		#expect(HamName.forOnboarding("Attic Heltec") == "//Attic Heltec")
	}

	@Test func unlicensingFlattensAnIncompleteHamName() {
		#expect(HamName.forUnlicensing("//Attic Heltec") == "Attic Heltec")
	}

	@Test func rejectsWhitespaceOnlyCallSigns() {
		#expect(!HamName.hasCallSign(" \n"))
	}
}
