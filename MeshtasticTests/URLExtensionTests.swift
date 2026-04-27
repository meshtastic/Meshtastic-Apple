import Foundation
import Testing

@testable import Meshtastic

// MARK: - URL Query Parameter Subscript

@Suite("URL Query Parameter Subscript")
struct URLQueryParamTests {

	@Test func standardQueryParam_returnsValue() {
		let url = URL(string: "https://example.com?name=Alice&age=30")!
		#expect(url["name"] == "Alice")
		#expect(url["age"] == "30")
	}

	@Test func missingQueryParam_returnsNil() {
		let url = URL(string: "https://example.com?name=Alice")!
		#expect(url["missing"] == nil)
	}

	@Test func noQueryParams_returnsNil() {
		let url = URL(string: "https://example.com")!
		#expect(url["anything"] == nil)
	}

	@Test func fragmentQueryParam_returnsValue() {
		let url = URL(string: "https://example.com#page?key=value&other=123")!
		#expect(url["key"] == "value")
		#expect(url["other"] == "123")
	}

	@Test func emptyValue_returnsEmptyString() {
		let url = URL(string: "https://example.com?key=")!
		#expect(url["key"] == "")
	}
}

// MARK: - URL queryParameters

@Suite("URL queryParameters Dictionary")
struct URLQueryParametersTests {

	@Test func multipleParams_returnsDictionary() {
		let url = URL(string: "https://example.com?a=1&b=2&c=3")!
		let params = url.queryParameters
		#expect(params?["a"] == "1")
		#expect(params?["b"] == "2")
		#expect(params?["c"] == "3")
	}

	@Test func noParams_returnsNil() {
		let url = URL(string: "https://example.com")!
		#expect(url.queryParameters == nil)
	}

	@Test func singleParam_returnsDictionary() {
		let url = URL(string: "https://example.com?key=value")!
		let params = url.queryParameters
		#expect(params?.count == 1)
		#expect(params?["key"] == "value")
	}

	@Test func duplicateKeys_lastWins() {
		let url = URL(string: "https://example.com?key=first&key=second")!
		let params = url.queryParameters
		// The loop overwrites, so last value wins
		#expect(params?["key"] == "second")
	}
}
