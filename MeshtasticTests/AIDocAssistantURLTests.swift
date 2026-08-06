import Foundation
import Testing

@testable import Meshtastic

@Suite("AI documentation search URLs")
struct AIDocAssistantURLTests {

	@Test(arguments: [
		("100% coverage", "https://meshtastic.org/search/?q=100%25%20coverage"),
		("mesh & mqtt", "https://meshtastic.org/search/?q=mesh%20%26%20mqtt"),
		("C++", "https://meshtastic.org/search/?q=C%2B%2B"),
		("topic#one", "https://meshtastic.org/search/?q=topic%23one")
	])
	func webSearchURL_encodesQueryValue(query: String, expectedURL: String) throws {
		let url = try #require(AIDocSearchURLBuilder.url(for: query))
		#expect(url.absoluteString == expectedURL)

		let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
		let queryValue = components.queryItems?.first(where: { $0.name == "q" })?.value
		#expect(queryValue == query)
	}

	@Test func webSearchURL_trimsQuery() throws {
		let url = try #require(AIDocSearchURLBuilder.url(for: "  mesh radio  \n"))
		let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
		#expect(components.queryItems?.first?.value == "mesh radio")
	}

	@Test func webSearchURL_rejectsEmptyQuery() {
		#expect(AIDocSearchURLBuilder.url(for: " \n\t ") == nil)
	}
}
