// CoordinatedSaveGuardTests.swift
// MeshtasticTests

import Foundation
import Testing

private let rawModelContextSavePattern = #"\b(?:[A-Za-z_][A-Za-z0-9_]*\.)*(?:context|[A-Za-z_][A-Za-z0-9_]*Context)(?:\?|!)?\.save\(\)"#

@Suite("Coordinated SwiftData saves")
struct CoordinatedSaveGuardTests {

	@Test("raw-save matcher recognizes context receiver variants")
	func rawSaveMatcherRecognizesContextReceiverVariants() throws {
		let expression = try NSRegularExpression(pattern: rawModelContextSavePattern)
		let rawSaves = [
			"try context.save()",
			"try modelContext.save()",
			"try backgroundContext.save()",
			"try store.context.save()",
			"try self.importContext.save()",
			"try context?.save()",
			"try self.importContext!.save()"
		]

		for rawSave in rawSaves {
			let range = NSRange(rawSave.startIndex..<rawSave.endIndex, in: rawSave)
			#expect(expression.firstMatch(in: rawSave, range: range) != nil)
		}
	}

	@Test("runtime ModelContext saves use the coordinator")
	func runtimeModelContextSavesUseCoordinator() throws {
		let repositoryRoot = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
		let sourceRoot = repositoryRoot.appendingPathComponent("Meshtastic", isDirectory: true)
		let expression = try NSRegularExpression(pattern: rawModelContextSavePattern)
		var violations: [String] = []

		let enumerator = FileManager.default.enumerator(
			at: sourceRoot,
			includingPropertiesForKeys: [.isRegularFileKey],
			options: [.skipsHiddenFiles]
		)
		while let fileURL = enumerator?.nextObject() as? URL {
			guard fileURL.pathExtension == "swift",
			      !fileURL.pathComponents.contains("Resources") else { continue }
			let contents = try String(contentsOf: fileURL, encoding: .utf8)
			for (index, line) in contents.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
				let text = String(line)
				let trimmed = text.trimmingCharacters(in: .whitespaces)
				guard !trimmed.hasPrefix("//"),
				      !text.contains("coordinated-save-allow") else { continue }
				let range = NSRange(text.startIndex..<text.endIndex, in: text)
				if expression.firstMatch(in: text, range: range) != nil {
					let relativePath = fileURL.path.replacingOccurrences(
						of: repositoryRoot.path + "/",
						with: ""
					)
					violations.append("\(relativePath):\(index + 1)")
				}
			}
		}

		#expect(
			violations.isEmpty,
			"Raw ModelContext saves bypass the container coordinator: \(violations.joined(separator: ", "))"
		)
	}
}
