//
//  AudioConfig.swift
//  Meshtastic
//
//  Audio module configuration for Codec2 voice communication.
//

import MeshtasticProtobufs
import OSLog
import SwiftUI

struct AudioConfig: View {

	@Environment(\.modelContext) private var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.dismiss) private var goBack

	let node: NodeInfoEntity?

	@State var hasChanges = false
	@State var codec2Enabled = false
	@State var pttPin = 0
	@State var bitrate = 0
	@State var i2sWs = 0
	@State var i2sSd = 0
	@State var i2sDin = 0
	@State var i2sSck = 0

	var body: some View {
		VStack {
			Form {
				ConfigHeader(title: "Audio", config: \.audioConfig, node: node, onAppear: setAudioValues)

				Section(header: Text("Options")) {
					Toggle(isOn: $codec2Enabled) {
						Label("Codec2 Enabled", systemImage: "waveform")
						Text("Enable Codec2 audio encoding/decoding for voice communication over the mesh.")
					}
					.tint(.accentColor)
				}

				if codec2Enabled {
					Section(header: Text("Codec2 Settings")) {
						Picker("Bitrate", selection: $bitrate) {
							Text("Default").tag(0)
							Text("3200 bps").tag(1)
							Text("2400 bps").tag(2)
							Text("1600 bps").tag(3)
							Text("1400 bps").tag(4)
							Text("1300 bps").tag(5)
							Text("1200 bps").tag(6)
							Text("700 bps").tag(7)
							Text("700B bps").tag(8)
						}
						Text("The audio sample rate to use for Codec2. Lower bitrates use less bandwidth but reduce audio quality.")
							.foregroundColor(.gray)
							.font(.callout)
					}

					Section(header: Text("GPIO Configuration")) {
						HStack {
							Label("PTT Pin", systemImage: "button.horizontal")
							Spacer()
							TextField("GPIO", value: $pttPin, format: .number)
								.frame(width: 80)
								.multilineTextAlignment(.trailing)
								.keyboardType(.numberPad)
						}
						Text("Push-to-talk GPIO pin number.")
							.foregroundColor(.gray)
							.font(.callout)

						HStack {
							Label("I2S WS", systemImage: "point.3.connected.trianglepath.dotted")
							Spacer()
							TextField("GPIO", value: $i2sWs, format: .number)
								.frame(width: 80)
								.multilineTextAlignment(.trailing)
								.keyboardType(.numberPad)
						}
						Text("I2S word select pin.")
							.foregroundColor(.gray)
							.font(.callout)

						HStack {
							Label("I2S SD", systemImage: "point.3.connected.trianglepath.dotted")
							Spacer()
							TextField("GPIO", value: $i2sSd, format: .number)
								.frame(width: 80)
								.multilineTextAlignment(.trailing)
								.keyboardType(.numberPad)
						}
						Text("I2S serial data pin.")
							.foregroundColor(.gray)
							.font(.callout)

						HStack {
							Label("I2S DIN", systemImage: "point.3.connected.trianglepath.dotted")
							Spacer()
							TextField("GPIO", value: $i2sDin, format: .number)
								.frame(width: 80)
								.multilineTextAlignment(.trailing)
								.keyboardType(.numberPad)
						}
						Text("I2S data in pin.")
							.foregroundColor(.gray)
							.font(.callout)

						HStack {
							Label("I2S SCK", systemImage: "point.3.connected.trianglepath.dotted")
							Spacer()
							TextField("GPIO", value: $i2sSck, format: .number)
								.frame(width: 80)
								.multilineTextAlignment(.trailing)
								.keyboardType(.numberPad)
						}
						Text("I2S serial clock pin.")
							.foregroundColor(.gray)
							.font(.callout)
					}
				}
			}
			.scrollDismissesKeyboard(.immediately)
			.disabled(!accessoryManager.isConnected || node?.audioConfig == nil)
			.safeAreaInset(edge: .bottom, alignment: .center) {
				HStack(spacing: 0) {
				SaveConfigButton(node: node, hasChanges: $hasChanges) {
					performConfigSave(
						node: node,
						context: context,
						accessoryManager: accessoryManager,
						hasChanges: $hasChanges,
						dismiss: goBack
					) { fromUser, toUser in
						var ac = ModuleConfig.AudioConfig()
						ac.codec2Enabled = codec2Enabled
						ac.pttPin = UInt32(pttPin)
						ac.bitrate = ModuleConfig.AudioConfig.Audio_Baud(rawValue: bitrate) ?? .codec2Default
						ac.i2SWs = UInt32(i2sWs)
						ac.i2SSd = UInt32(i2sSd)
						ac.i2SDin = UInt32(i2sDin)
						ac.i2SSck = UInt32(i2sSck)
						_ = try await accessoryManager.saveAudioModuleConfig(config: ac, fromUser: fromUser, toUser: toUser)
					}
				}
				}
			}
			.navigationTitle("Audio Config")
			.toolbar {
				ToolbarItem(placement: .topBarTrailing) {
					ConnectedDevice(deviceConnected: accessoryManager.isConnected, name: accessoryManager.activeConnection?.device.shortName ?? "?")
				}
			}
			.onFirstAppear {
				requestRemoteConfig(
					node: node,
					context: context,
					accessoryManager: accessoryManager,
					configIsNil: { $0.audioConfig == nil },
					request: accessoryManager.requestAudioModuleConfig
				)
			}
			.onChange(of: codec2Enabled) { oldVal, newVal in
				if oldVal != newVal && newVal != node?.audioConfig?.codec2Enabled ?? false { hasChanges = true }
			}
			.onChange(of: pttPin) { oldVal, newVal in
				if oldVal != newVal && newVal != Int(node?.audioConfig?.pttPin ?? 0) { hasChanges = true }
			}
			.onChange(of: bitrate) { oldVal, newVal in
				if oldVal != newVal && newVal != Int(node?.audioConfig?.bitrate ?? 0) { hasChanges = true }
			}
			.onChange(of: i2sWs) { oldVal, newVal in
				if oldVal != newVal && newVal != Int(node?.audioConfig?.i2sWs ?? 0) { hasChanges = true }
			}
			.onChange(of: i2sSd) { oldVal, newVal in
				if oldVal != newVal && newVal != Int(node?.audioConfig?.i2sSd ?? 0) { hasChanges = true }
			}
			.onChange(of: i2sDin) { oldVal, newVal in
				if oldVal != newVal && newVal != Int(node?.audioConfig?.i2sDin ?? 0) { hasChanges = true }
			}
			.onChange(of: i2sSck) { oldVal, newVal in
				if oldVal != newVal && newVal != Int(node?.audioConfig?.i2sSck ?? 0) { hasChanges = true }
			}
		}
	}

	func setAudioValues() {
		self.codec2Enabled = node?.audioConfig?.codec2Enabled ?? false
		self.pttPin = Int(node?.audioConfig?.pttPin ?? 0)
		self.bitrate = Int(node?.audioConfig?.bitrate ?? 0)
		self.i2sWs = Int(node?.audioConfig?.i2sWs ?? 0)
		self.i2sSd = Int(node?.audioConfig?.i2sSd ?? 0)
		self.i2sDin = Int(node?.audioConfig?.i2sDin ?? 0)
		self.i2sSck = Int(node?.audioConfig?.i2sSck ?? 0)
		self.hasChanges = false
	}
}

#Preview {
	AudioConfig(node: nil)
		.environmentObject(AccessoryManager.shared)
		.modelContainer(PersistenceController.preview.container)
}
