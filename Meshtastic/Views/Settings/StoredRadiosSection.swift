//
//  StoredRadiosSection.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import SwiftData
import SwiftUI

/// App Settings › Your Radios (feature 021, T187): the user's radios that aren't connected, with
/// Remove This Radio for each. A radio that died, was given away, or is only known from an old
/// backup would otherwise stay one of the user's radios for good: its broadcasts are stored as
/// the user's own and never notify. A connected radio is removed from Settings › Device.
/// Only shown once the app knows more than one radio.
struct StoredRadiosSection: View {
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Query(sort: \MyInfoEntity.myNodeNum) private var radios: [MyInfoEntity]
	@State private var radioToRemove: MyInfoEntity?
	@State private var removing: Set<Int64> = []

	/// Radios neither connected nor connecting (T197): removing one that's connecting would delete
	/// its data while its connect goes on writing for it.
	private var offlineRadios: [MyInfoEntity] {
		let connecting = accessoryManager.connectAttempts.values
		return radios.filter { radio in
			radio.myNodeNum != 0
				&& !accessoryManager.isRadioConnected(nodeNum: radio.myNodeNum)
				&& !connecting.contains { $0.device.num == radio.myNodeNum || $0.device.id.uuidString == radio.peripheralId }
		}
	}

	private func name(_ radio: MyInfoEntity) -> String {
		let user = radio.myInfoNode?.user
		return user?.longName ?? user?.shortName ?? radio.bleName ?? radio.myNodeNum.toHex()
	}

	var body: some View {
		if radios.filter({ $0.myNodeNum != 0 }).count > 1, !offlineRadios.isEmpty {
			Section {
				ForEach(offlineRadios, id: \.myNodeNum) { radio in
					HStack {
						VStack(alignment: .leading, spacing: 2) {
							Text(name(radio))
							if let lastConnected = radio.lastConnected {
								Text("Last connected \(lastConnected.formatted(date: .abbreviated, time: .shortened))")
									.font(.caption)
									.foregroundStyle(.secondary)
							} else {
								// The store's own radio before its first connect since the update, a
								// merged backup's radio, or a row an older version left (T197).
								Text("Not connected since the update")
									.font(.caption)
									.foregroundStyle(.secondary)
							}
						}
						Spacer()
						if removing.contains(radio.myNodeNum) {
							ProgressView()
						} else {
							Button("Remove", role: .destructive) { radioToRemove = radio }
								.buttonStyle(.borderless)
						}
					}
				}
			} header: {
				Text("Your Radios")
			} footer: {
				Text("Radios the app knows that aren't connected now. Remove one you no longer have, such as a radio that stopped working or that you gave away.")
			}
			.confirmationDialog(
				"Remove \(radioToRemove.map(name) ?? "")?",
				isPresented: Binding(get: { radioToRemove != nil }, set: { if !$0 { radioToRemove = nil } }),
				titleVisibility: .visible,
				presenting: radioToRemove
			) { radio in
				Button("Remove This Radio", role: .destructive) { remove(radio.myNodeNum) }
			} message: { _ in
				Text("It's no longer one of your radios and isn't reconnected. Its direct messages go, and messages on channels none of your other radios has. When it was on a mesh of its own, the nodes only it heard go too.")
			}
		}
	}

	private func remove(_ radioNum: Int64) {
		removing.insert(radioNum)
		Task {
			await accessoryManager.removeRadio(radioNum)
			removing.remove(radioNum)
		}
	}
}
