//
//  CsvDocument.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 7/15/22.
//

import SwiftUI
import UniformTypeIdentifiers

struct CsvDocument: FileDocument {

	static var readableContentTypes =  [UTType.commaSeparatedText]

	@State var csvData: String

	init(emptyCsv: String = "" ) {

		csvData = emptyCsv
	}

	init(configuration: ReadConfiguration) throws {

		if let data = configuration.file.regularFileContents {

			csvData = String(decoding: data, as: UTF8.self)

		} else {

			throw CocoaError(.fileReadCorruptFile)
		}
	}

	func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
		let data = Data(csvData.utf8)
		return FileWrapper(regularFileWithContents: data)
	}
}
