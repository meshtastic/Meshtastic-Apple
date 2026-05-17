// IntentConverterTests.swift
// MeshtasticTests

#if os(iOS)
import Testing
import Foundation
@testable import Meshtastic

// MARK: - IntentMessageConverters Pure Logic Tests

@Suite("IntentMessageConverters directMessageNodeNum")
struct IntentDirectMessageNodeNumTests {

	@Test func numericString_returnsInt64() {
		let result = IntentMessageConverters.directMessageNodeNum(from: "12345")
		#expect(result == 12345)
	}

	@Test func meshtasticDomain_stripsAndReturns() {
		let result = IntentMessageConverters.directMessageNodeNum(from: "98765@meshtastic.local")
		#expect(result == 98765)
	}

	@Test func nonNumericString_returnsNil() {
		let result = IntentMessageConverters.directMessageNodeNum(from: "hello")
		#expect(result == nil)
	}

	@Test func emptyString_returnsNil() {
		let result = IntentMessageConverters.directMessageNodeNum(from: "")
		#expect(result == nil)
	}

	@Test func zero_returnsZero() {
		let result = IntentMessageConverters.directMessageNodeNum(from: "0")
		#expect(result == 0)
	}

	@Test func largeNumber_returnsCorrectValue() {
		let result = IntentMessageConverters.directMessageNodeNum(from: "4294967295")
		#expect(result == 4294967295)
	}

	@Test func domainSuffix_nonNumericPrefix_returnsNil() {
		let result = IntentMessageConverters.directMessageNodeNum(from: "abc@meshtastic.local")
		#expect(result == nil)
	}
}

// MARK: - channelIndex(fromHandleOrName:)

@Suite("IntentMessageConverters channelIndex")
struct IntentChannelIndexTests {

	@Test func primaryChannel_returnsZero() {
		let result = IntentMessageConverters.channelIndex(fromHandleOrName: "Primary Channel")
		#expect(result == 0)
	}

	@Test func primaryChannel_caseInsensitive() {
		let result = IntentMessageConverters.channelIndex(fromHandleOrName: "primary channel")
		#expect(result == 0)
	}

	@Test func channelN_returnsIndex() {
		let result = IntentMessageConverters.channelIndex(fromHandleOrName: "Channel 3")
		#expect(result == 3)
	}

	@Test func channelDashN_returnsIndex() {
		let result = IntentMessageConverters.channelIndex(fromHandleOrName: "channel-5")
		#expect(result == 5)
	}

	@Test func channelDashN_withDomain() {
		let result = IntentMessageConverters.channelIndex(fromHandleOrName: "channel-2@meshtastic.local")
		#expect(result == 2)
	}

	@Test func arbitraryName_returnsNil() {
		let result = IntentMessageConverters.channelIndex(fromHandleOrName: "MyCustomChannel")
		#expect(result == nil)
	}

	@Test func emptyString_returnsNil() {
		let result = IntentMessageConverters.channelIndex(fromHandleOrName: "")
		#expect(result == nil)
	}
}

// MARK: - channelDisplayName

@Suite("IntentMessageConverters channelDisplayName")
struct IntentChannelDisplayNameTests {

	@Test func withName_returnsName() {
		let result = IntentMessageConverters.channelDisplayName(for: 1, named: "MyChannel")
		#expect(result == "MyChannel")
	}

	@Test func emptyName_index0_returnsPrimaryChannel() {
		let result = IntentMessageConverters.channelDisplayName(for: 0, named: "")
		#expect(result == "Primary Channel")
	}

	@Test func nilName_index0_returnsPrimaryChannel() {
		let result = IntentMessageConverters.channelDisplayName(for: 0, named: nil)
		#expect(result == "Primary Channel")
	}

	@Test func nilName_nonZeroIndex_returnsChannelN() {
		let result = IntentMessageConverters.channelDisplayName(for: 3, named: nil)
		#expect(result == "Channel 3")
	}

	@Test func emptyName_nonZeroIndex_returnsChannelN() {
		let result = IntentMessageConverters.channelDisplayName(for: 7, named: "")
		#expect(result == "Channel 7")
	}
}

// MARK: - meshtasticDomain constant

@Suite("IntentMessageConverters Constants")
struct IntentConverterConstantsTests {

	@Test func meshtasticDomain_value() {
		#expect(IntentMessageConverters.meshtasticDomain == "@meshtastic.local")
	}
}
#endif
