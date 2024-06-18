//
//  BackupData.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 6/8/24.
//

import SwiftUI
import OSLog
import CoreData
import Foundation

struct BackupData: View {
	
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@State private var files = [URL]()
	private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }

	var body: some View {
		VStack {
			Button(action: {
				let container = NSPersistentContainer(name : "Meshtastic")
				guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
					Logger.data.error("nil File path for back")
					return
				}
				do {
					try container.copyPersistentStores(to: url.appendingPathComponent("backups").appendingPathComponent("\(UserDefaults.preferredPeripheralNum)"), overwriting: true)
					loadFiles()
					Logger.data.notice("🗂️ Made a core data backup to backup/\(UserDefaults.preferredPeripheralNum)")
				} catch {
					Logger.data.error("Copy error: \(error.localizedDescription)")
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
			
		}
		Text("Files")
			.font(.title)
		List(files, id: \.self) { file in
			if file.pathExtension.contains("sqlite") { //} == "sqlite" {
				//Text(file.absoluteString)
				Label {
					Text("\(file.pathComponents[10])/\(file.lastPathComponent)")
						.swipeActions {
							Button(role: .none) {
								bleManager.disconnectPeripheral(reconnect: false)
								
								let container = NSPersistentContainer(name : "Meshtastic")
								guard let storeUrl = container.persistentStoreDescriptions.first?.url else {
									return
								}
								guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
									Logger.data.error("nil File path for back")
									return
								}
								do {
									context.reset()
									try container.restorePersistentStore(from: file.absoluteURL)
									
									UserDefaults.preferredPeripheralId = ""
									UserDefaults.preferredPeripheralNum = Int(file.pathComponents[10]) ?? 0
									Logger.data.notice("🗂️ Restored a core data backup to backup/\(UserDefaults.preferredPeripheralNum)")
								} catch {
									Logger.data.error("Copy error: \(error.localizedDescription)")
								}
							} label: {
								Label("restore", systemImage: "arrow.counterclockwise")
							}
							Button(role: .destructive) {
								do {
									try FileManager.default.removeItem(at: file)
								} catch {
									Logger.data.error("Error deleting backup file: \(error.localizedDescription)")
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
			}
			else {
				Label {
					Text("\(file.lastPathComponent)")
						.swipeActions {
							Button(role: .destructive) {
								do {
									try FileManager.default.removeItem(at: file)
								} catch {
									Logger.data.error("Error deleting backup file: \(error.localizedDescription)")
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
		.navigationBarTitle("Data", displayMode: .inline)
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
					let fileAttributes = try fileURL.resourceValues(forKeys:[.isRegularFileKey])
					if fileAttributes.isRegularFile! {
						files.append(fileURL)
					}
				} catch {
					Logger.data.error("Error loading backup files at \(fileURL.absoluteString) \(error.localizedDescription)")
				}
			}
		}
	}
}
