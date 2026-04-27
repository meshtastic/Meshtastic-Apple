import Foundation
import Testing

@testable import Meshtastic

// MARK: - Int.numberOfDigits

@Suite("Int numberOfDigits")
struct IntDigitsTests {

	@Test func singleDigit_returnsOne() {
		#expect(0.numberOfDigits() == 1)
		#expect(5.numberOfDigits() == 1)
		#expect(9.numberOfDigits() == 1)
	}

	@Test func multipleDigits_returnsCorrectCount() {
		#expect(10.numberOfDigits() == 2)
		#expect(99.numberOfDigits() == 2)
		#expect(100.numberOfDigits() == 3)
		#expect(1234.numberOfDigits() == 4)
	}

	@Test func negativeNumbers_countsAbsoluteDigits() {
		#expect((-5).numberOfDigits() == 1)
		#expect((-42).numberOfDigits() == 2)
		#expect((-999).numberOfDigits() == 3)
	}

	@Test func largeNumber_returnsCorrectCount() {
		#expect(1_000_000.numberOfDigits() == 7)
	}
}

// MARK: - UInt32.toHex

@Suite("UInt32 toHex")
struct UInt32HexTests {

	@Test func zero_formatsWithPrefix() {
		#expect(UInt32(0).toHex() == "!00000000")
	}

	@Test func smallNumber_padsToEightDigits() {
		#expect(UInt32(255).toHex() == "!000000ff")
	}

	@Test func maxValue_formatsCorrectly() {
		#expect(UInt32.max.toHex() == "!ffffffff")
	}

	@Test func typicalNodeNum_formatsCorrectly() {
		#expect(UInt32(0xDEADBEEF).toHex() == "!deadbeef")
	}

	@Test func result_startsWithExclamation() {
		#expect(UInt32(42).toHex().hasPrefix("!"))
	}

	@Test func result_isLowercase() {
		let hex = UInt32(0xABCD).toHex()
		#expect(hex == hex.lowercased())
	}
}

// MARK: - Int64.toHex

@Suite("Int64 toHex")
struct Int64HexTests {

	@Test func zero_formatsWithPrefix() {
		#expect(Int64(0).toHex() == "!00000000")
	}

	@Test func positiveValue_formatsCorrectly() {
		#expect(Int64(0xABCD1234).toHex() == "!abcd1234")
	}

	@Test func result_startsWithExclamation() {
		#expect(Int64(1).toHex().hasPrefix("!"))
	}

	@Test func result_isLowercase() {
		let hex = Int64(0xFACE).toHex()
		#expect(hex == hex.lowercased())
	}
}

// MARK: - Data Extensions

@Suite("Data macAddressString")
struct DataMacAddressTests {

	@Test func sixBytes_formatsWithColons() {
		let data = Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])
		#expect(data.macAddressString == "aa:bb:cc:dd:ee:ff")
	}

	@Test func singleByte_noColon() {
		let data = Data([0x42])
		#expect(data.macAddressString == "42")
	}

	@Test func emptyData_returnsEmpty() {
		let data = Data()
		#expect(data.macAddressString == "")
	}

	@Test func allZeros_formatsCorrectly() {
		let data = Data([0x00, 0x00, 0x00])
		#expect(data.macAddressString == "00:00:00")
	}
}

@Suite("Data hexDescription")
struct DataHexDescriptionTests {

	@Test func typicalBytes_formatsWithoutSeparators() {
		let data = Data([0xAB, 0xCD, 0xEF])
		#expect(data.hexDescription == "abcdef")
	}

	@Test func singleByte_twoCharacters() {
		let data = Data([0x0F])
		#expect(data.hexDescription == "0f")
	}

	@Test func emptyData_returnsEmpty() {
		let data = Data()
		#expect(data.hexDescription == "")
	}

	@Test func allZeros_formatsCorrectly() {
		let data = Data([0x00, 0x00])
		#expect(data.hexDescription == "0000")
	}

	@Test func fullRange_formatsCorrectly() {
		let data = Data([0xFF, 0x00, 0x80])
		#expect(data.hexDescription == "ff0080")
	}
}
