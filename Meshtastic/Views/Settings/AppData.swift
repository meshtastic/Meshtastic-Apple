//
//  AppData.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 6/8/24.
//

import SwiftUI
import OSLog
import CoreData
import Foundation

struct AppData: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@State private var files = [URL]()
	private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }

	var body: some View {

		VStack {

			Section(header: Text("Phone GPS")) {
				GPSStatus()
			}
			Divider()
		}

		List(files, id: \.self) { file in
			HStack {
				VStack(alignment: .leading ) {
					if file.pathExtension.contains("sqlite") {
						Label {
							Text("Node Core Data Backup \(file.pathComponents[(idiom == .phone || idiom == .pad) ? 9 : 10])/\(file.lastPathComponent) - \(file.creationDate?.formatted() ?? "") - \(file.fileSizeString)")
								.swipeActions {
									Button(role: .destructive) {
										do {
											try FileManager.default.removeItem(at: file)
										} catch {
											Logger.services.error("🗑️ Delete file error: \(error, privacy: .public)")
										}
									} label: {
										Label("Delete", systemImage: "trash")
									}
								}
						} icon: {
							Image(systemName: "cylinder.split.1x2")
								.symbolRenderingMode(.hierarchical)
								.font(idiom == .phone ? .callout : .title)
								.frame(width: 35)
						}
					} else {
						Label {
							Text("\(file.lastPathComponent) - \(file.creationDate?.formatted() ?? "") - \(file.fileSizeString)")
								.swipeActions {
									Button(role: .destructive) {
										do {
											try FileManager.default.removeItem(at: file)
										} catch {
											Logger.services.error("🗑️ Delete file error: \(error, privacy: .public)")
										}
									} label: {
										Label("Delete", systemImage: "trash")
									}
								}
						} icon: {
							Image(systemName: "doc.text")
								.symbolRenderingMode(.hierarchical)
								.font(idiom == .phone ? .callout : .title)
								.frame(width: 35)
						}
					}
				}
#if targetEnvironment(macCatalyst)
				Spacer()
				VStack(alignment: .trailing) {
					Button {
						do {
							try FileManager.default.removeItem(at: file)
							loadFiles()
						} catch {
							Logger.services.error("🗑️ Delete file error: \(error, privacy: .public)")
						}
					} label: {
						Label("", systemImage: "trash")
					}
				}
#endif
			}
		}
		.navigationBarTitle("File Storage", displayMode: .inline)
		.onAppear(perform: {
			loadFiles()
		})
		.listStyle(.inset)
	}

	private func loadFiles() {
		files = []
		guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
			Logger.data.error("🗂️ nil default document directory path for backup, core data backup failed.")
			return
		}
		if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
			for case let fileURL as URL in enumerator {
				do {
					let fileAttributes = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
					if fileAttributes.isRegularFile! {
						files.append(fileURL)
					}
				} catch {
					Logger.services.error("📁 Load file: \(fileURL, privacy: .public) error: \(error, privacy: .public)")
				}
			}
		}
	}
}
