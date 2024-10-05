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

			Section(header: Text("phone.gps")) {
				GPSStatus()
			}
			Divider()
			Button(action: {
				let container = NSPersistentContainer(name: "Meshtastic")
				guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
					Logger.data.error("nil File path for back")
					return
				}
				do {
					try container.copyPersistentStores(to: url.appendingPathComponent("backup").appendingPathComponent("\(UserDefaults.preferredPeripheralNum)"), overwriting: true)
					loadFiles()
					Logger.data.notice("🗂️ Made a core data backup to backup/\(UserDefaults.preferredPeripheralNum)")
				} catch {
					Logger.data.error("🗂️ Core data backup copy error: \(error, privacy: .public)")
				}
			}) {
				Label {
					Text("Backup Database")
						.font(idiom == .phone ? .callout : .title)
				} icon: {
					Image(systemName: "cylinder.split.1x2")
						.symbolRenderingMode(.hierarchical)
						.font(idiom == .phone ? .callout : .title)
						.frame(width: 35)
				}
			}
			.buttonStyle(.bordered)
			.buttonBorderShape(.capsule)
			.controlSize(.large)
			Divider()
		}

		List(files, id: \.self) { file in
			HStack {
				VStack(alignment: .leading ) {
					if file.pathExtension.contains("sqlite") {
						Label {
							Text("Node Core Data Backup \(file.pathComponents[(idiom == .phone || idiom == .pad) ? 9 : 10])/\(file.lastPathComponent) - \(file.creationDate?.formatted() ?? "") - \(file.fileSizeString)")
								.swipeActions {
									Button(role: .none) {
										bleManager.disconnectPeripheral(reconnect: false)
										let container = NSPersistentContainer(name: "Meshtastic")
										do {
											try container.restorePersistentStore(from: file.absoluteURL)
											let request = MyInfoEntity.fetchRequest()
											try context.fetch(request)
											UserDefaults.preferredPeripheralId = ""
											UserDefaults.preferredPeripheralNum = Int(file.pathComponents[(idiom == .phone || idiom == .pad) ? 9 : 10]) ?? 0
											Logger.data.notice("🗂️ Restored a core data backup to backup/\(UserDefaults.preferredPeripheralNum, privacy: .public)")
										} catch {
											Logger.data.error("🗂️ Core data restore copy error: \(error, privacy: .public)")
										}
									} label: {
										Label("restore", systemImage: "arrow.counterclockwise")
									}
									Button(role: .destructive) {
										do {
											try FileManager.default.removeItem(at: file)
										} catch {
											Logger.services.error("🗑️ Delete file error: \(error, privacy: .public)")
										}
									} label: {
										Label("delete", systemImage: "trash")
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
										Label("delete", systemImage: "trash")
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
