import Testing
@testable import Meshtastic

@Suite("App icon picker")
@MainActor
struct AppIconPickerTests {
	@Test("Options have a stable user-facing order")
	func optionsHaveStableOrder() {
		#expect(AppIconPicker.iconOptions.map(\.description) == [
			"Default",
			"Meshtastic Powered",
			"Chirpy",
			"Ham"
		])
		#expect(AppIconPicker.iconOptions.map(\.iconName) == [
			nil,
			"AppIcon_MPowered",
			"AppIcon_Chirpy",
			"AppIcon_Ham"
		])
	}

	@Test("Options have unique stable identifiers and alternate icon names")
	func optionsAreUnique() {
		let identifiers = AppIconPicker.iconOptions.map(\.id)
		let alternateNames = AppIconPicker.iconOptions.compactMap(\.iconName)

		#expect(Set(identifiers).count == identifiers.count)
		#expect(Set(alternateNames).count == alternateNames.count)
	}
}
