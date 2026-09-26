//
//  ADCOverrideTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 9/26/26.
//
import Testing
@testable import Meshtastic

/// The power screen's ADC override is a switch over a single number, where zero means off.
///
/// The switch used to keep its own copy of that state, taken on appear — before the form had
/// loaded the config — so a radio with an override stored showed the switch off. Reading the
/// number instead is what fixes it, and these cover the rules that reading depends on.
@Suite("ADC override")
struct ADCOverrideTests {

	@Test func theSwitchReadsTheStoredMultiplier() {
		// The case that was broken on screen: a stored override has to read as on.
		#expect(ADCOverride.isOn(3.2))
		#expect(ADCOverride.isOn(2))
		#expect(!ADCOverride.isOn(0), "zero is how the message stores no override")
	}

	@Test func switchingOffStoresZero() {
		#expect(ADCOverride.multiplier(switchedOn: false, remembered: 3.2) == 0)
		#expect(ADCOverride.multiplier(switchedOn: false, remembered: 0) == 0)
	}

	@Test func switchingOnRestoresTheNumberItHad() {
		#expect(ADCOverride.multiplier(switchedOn: true, remembered: 3.2) == 3.2)
	}

	@Test func switchingOnWithNothingToRestoreStartsInRange() {
		// Not zero. Leaving it at zero is what the old field did, which made the switch read
		// as on while the message said no override — it would have saved as off.
		let started = ADCOverride.multiplier(switchedOn: true, remembered: 0)
		#expect(started != 0)
		#expect(ADCOverride.isOn(started), "switching on has to leave the switch on")
		#expect(started >= 2 && started <= 6, "the range the field documents")
	}
}
