//
//  Channels.swift
//  Meshtastic Apple
//
//  Copyright(c) Garth Vander Houwen 4/8/22.
//

@preconcurrency import SwiftData
import MapKit
import MeshtasticProtobufs
import OSLog
import SwiftUI
import TipKit

func generateChannelKey(size: Int) -> String {
	var keyData = Data(count: size)
	_ = keyData.withUnsafeMutableBytes {
	  SecRandomCopyBytes(kSecRandomDefault, size, $0.baseAddress!)
	}
	return keyData.base64EncodedString()
}

struct Channels: View {

	@Environment(\.modelContext) private var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.dismiss) private var goBack
	@Environment(\.sizeCategory) var sizeCategory
	@Environment(\.colorScheme) private var colorScheme

	@Bindable var node: NodeInfoEntity

	@State var hasChanges = false
	@State var hasValidKey = true
	@State private var isPresentingSaveConfirm: Bool = false
	@State var channelIndex: Int32 = 0
	@State var channelName = ""
	@State var channelKeySize = 16
	@State var channelKey = "AQ=="
	@State var channelRole = 0
	@State var uplink = false
	@State var downlink = false
	@State var positionPrecision = 32.0
	@State var preciseLocation = true
	@State var positionsEnabled = true
	@State var supportedVersion = true
	@State var selectedChannel: ChannelEntity?

	/// Minimum Version for granular position configuration
	@State var minimumVersion = "2.2.24"
	@State private var showingHelp = false

	private var displayChannels: [ChannelEntity] {
		guard let channels = node.myInfo?.channels else { return [] }
		var byIndex: [Int32: ChannelEntity] = [:]
		for channel in channels {
			byIndex[channel.index] = channel
		}
		return byIndex.values.sorted { $0.index < $1.index }
	}

	private var locationSharingChannelIndex: Int32? {
		if accessoryManager.checkIsVersionSupported(forVersion: "2.6.10") {
			return displayChannels.first { $0.positionPrecision > 0 }?.index
		}
		guard let primary = displayChannels.first(where: { $0.index == 0 || $0.role == 1 }),
			  primary.positionPrecision > 0 else {
			return nil
		}
		return primary.index
	}

	private var primaryChannelName: String {
		if let primary = displayChannels.first(where: { $0.index == 0 || $0.role == 1 }),
		   let name = primary.name,
		   !name.isEmpty {
			return name
		}
		if node.loRaConfig?.usePreset == false {
			return "Custom"
		}
		guard let preset = ModemPresets(rawValue: Int(node.loRaConfig?.modemPreset ?? 0)) else {
			return "LongFast"
		}
		return preset.androidChannelName
	}

	private var channelFrequencySummary: ChannelFrequencySummary? {
		ChannelFrequencySummary(loRaConfig: node.loRaConfig, primaryChannelName: primaryChannelName)
	}

	private func normalizeDuplicateChannelsIfNeeded() {
		guard let channels = node.myInfo?.channels else { return }
		var uniqueChannels: [Int32: ChannelEntity] = [:]
		for channel in channels {
			uniqueChannels[channel.index] = channel
		}
		let deduped = uniqueChannels.values.sorted { $0.index < $1.index }
		guard deduped.count != channels.count else { return }
		node.myInfo?.channels = deduped
		do {
			try context.save()
			Logger.data.info("💾 Normalized duplicate channels for node \(self.node.num, privacy: .public)")
		} catch {
			Logger.data.error("Failed normalizing duplicate channels: \(error.localizedDescription, privacy: .public)")
		}
	}

	var body: some View {

		VStack {
			List {
				TipView(CreateChannelsTip(), arrowEdge: .bottom)
					.tipBackground(colorScheme == .dark ? Color(.systemBackground) : Color(.secondarySystemBackground))
					.listRowSeparator(.hidden)
				if node.myInfo != nil {
					if let channelFrequencySummary {
						ChannelConfigSummaryRow(summary: channelFrequencySummary)
					}
					ForEach(displayChannels, id: \.self) { (channel: ChannelEntity) in
						Button(action: {
							channelIndex = channel.index
							channelRole = Int(channel.role)
							channelKey = channel.psk?.base64EncodedString() ?? ""
							if channelKey.count == 0 {
								channelKeySize = 0
							} else if channelKey == "AQ==" {
								channelKeySize = -1
							} else if channelKey.count == 4 {
								channelKeySize = 1
							} else if channelKey.count == 24 {
								channelKeySize = 16
							} else if channelKey.count == 32 {
								channelKeySize = 24
							} else if channelKey.count == 44 {
								channelKeySize = 32
							}
							channelName = channel.name ?? ""
							uplink = channel.uplinkEnabled
							downlink = channel.downlinkEnabled
							positionPrecision = Double(channel.positionPrecision)
							if !supportedVersion && channelRole == 1 {
								positionPrecision = 32
								preciseLocation = true
								positionsEnabled = true
								if channelKey == "AQ==" {
									positionPrecision = 14
									preciseLocation = false
								}
							} else if !supportedVersion && channelRole == 2 {
								positionPrecision = 0
								preciseLocation = false
								positionsEnabled = false
							} else {
								if channelKey == "AQ==" {
									preciseLocation = false
									if (positionPrecision > 0 && positionPrecision < 11) || positionPrecision > 14 {
										positionPrecision = 14
									}
								} else if positionPrecision == 32 {
									preciseLocation = true
									positionsEnabled = true
								} else {
									preciseLocation = false
								}
								if positionPrecision == 0 {
									positionsEnabled = false
								} else {
									positionsEnabled = true
								}
							}
							hasChanges = false
							selectedChannel = channel
						}) {
							ChannelRow(channel: channel, sharesLocation: channel.index == locationSharingChannelIndex)
						}
						.buttonStyle(.plain)
					}
				}
				if (node.myInfo?.channels.count ?? 0) < 8 {
					Button {
						let channelIndexes = node.myInfo?.channels.compactMap({ ch -> Int in
							return Int(ch.index)
						})
						let firstChannelIndex = firstMissingChannelIndex(channelIndexes ?? [])
						channelKeySize = 16
						let key = generateChannelKey(size: channelKeySize)
						channelName = ""
						channelIndex = Int32(firstChannelIndex)
						channelRole = 2
						channelKey = key
						positionsEnabled = false
						preciseLocation = false
						positionPrecision = 0
						uplink = false
						downlink = false

						let newChannel = ChannelEntity()
						newChannel.id = channelIndex
						newChannel.index = channelIndex
						newChannel.uplinkEnabled = uplink
						newChannel.downlinkEnabled = downlink
						newChannel.name = channelName
						newChannel.role = Int32(channelRole)
						newChannel.psk = Data(base64Encoded: channelKey) ?? Data()
						newChannel.positionPrecision = Int32(positionPrecision)
						selectedChannel = newChannel
						hasChanges = true

					} label: {
						Label("Add Channel", systemImage: "plus.square")
					}
					.buttonStyle(.bordered)
					.buttonBorderShape(.capsule)
					.controlSize(.large)
					.frame(maxWidth: .infinity)
					.padding(.vertical, 8)
				}
			}
			.sheet(item: $selectedChannel) { _ in
				#if targetEnvironment(macCatalyst)
				Text("Channel")
					.font(.largeTitle)
					.padding()
				#endif
				ChannelForm(channelIndex: $channelIndex, channelName: $channelName, channelKeySize: $channelKeySize, channelKey: $channelKey, channelRole: $channelRole, uplink: $uplink, downlink: $downlink, positionPrecision: $positionPrecision, preciseLocation: $preciseLocation, positionsEnabled: $positionsEnabled, hasChanges: $hasChanges, hasValidKey: $hasValidKey, supportedVersion: $supportedVersion)
					.presentationDetents([.large])
					#if !targetEnvironment(macCatalyst)
					.presentationDragIndicator(.visible)
					#endif
				.onFirstAppear {
					supportedVersion = accessoryManager.checkIsVersionSupported(forVersion: minimumVersion)
				}
				HStack {
					Button {
						var channel = Channel()
						channel.index = channelIndex
						channel.role = ChannelRoles(rawValue: channelRole)?.protoEnumValue() ?? .secondary
							channel.index = channelIndex
							channel.settings.name = channelName
							channel.settings.psk = Data(base64Encoded: channelKey) ?? Data()
							channel.settings.uplinkEnabled = uplink
							channel.settings.downlinkEnabled = downlink
							channel.settings.moduleSettings.positionPrecision = UInt32(positionPrecision)
							selectedChannel!.role = Int32(channelRole)
							selectedChannel!.index = channelIndex
							selectedChannel!.name = channelName
							selectedChannel!.psk = Data(base64Encoded: channelKey) ?? Data()
							selectedChannel!.uplinkEnabled = uplink
							selectedChannel!.downlinkEnabled = downlink
							selectedChannel!.positionPrecision = Int32(positionPrecision)

							guard var channels = node.myInfo?.channels else {
								return
							}
							if let idx = channels.firstIndex(where: { $0.index == selectedChannel?.index }) {
								channels[idx] = selectedChannel!
							} else {
								channels.append(selectedChannel!)
							}

							var uniqueChannels: [Int32: ChannelEntity] = [:]
							for channel in channels {
								uniqueChannels[channel.index] = channel
							}
							node.myInfo?.channels = uniqueChannels.values.sorted { $0.index < $1.index }
						if channel.role != Channel.Role.disabled {
							if let selected = selectedChannel, selected.modelContext == nil {
								context.insert(selected)
							}
							do {
								try context.save()
								Logger.data.info("💾 Saved Channel: \(channel.settings.name, privacy: .public)")
							} catch {
								let nsError = error as NSError
								Logger.data.error("Unresolved Core Data error in the channel editor. Error: \(nsError, privacy: .public)")
							}
						} else {
							let objects = selectedChannel?.allPrivateMessages ?? []
							for object in objects {
								context.delete(object)
							}
							let channelIdx = channel.index
							var nodeDescriptor = FetchDescriptor<NodeInfoEntity>(
								predicate: #Predicate { $0.channel == channelIdx }
							)
							nodeDescriptor.fetchLimit = 100
							if let matchingNodes = try? context.fetch(nodeDescriptor) {
								for matchingNode in matchingNodes {
									context.delete(matchingNode)
								}
							}
							context.delete(selectedChannel!)
							do {
								try context.save()
								Logger.data.info("💾 Deleted Channel: \(channel.settings.name, privacy: .public)")
							} catch {
								let nsError = error as NSError
								Logger.data.error("Unresolved Core Data error in the channel editor. Error: \(nsError, privacy: .public)")
							}
						}
						Task {
							_ = try await accessoryManager.saveChannel(channel: channel, fromUser: node.user!, toUser: node.user!)
							Task { @MainActor in
								selectedChannel = nil
								channelName = ""
								channelRole	= 2
								hasChanges = false
							}
							accessoryManager.mqttManager.connectFromConfigSettings(node: node)
						}
					} label: {
						Label("Save", systemImage: "square.and.arrow.down")
					}
					.disabled(!accessoryManager.isConnected)// || !hasChanges)// !hasValidKey)
					.buttonStyle(.bordered)
					.buttonBorderShape(.capsule)
					.controlSize(.large)
					.padding(.bottom)
					#if targetEnvironment(macCatalyst)
					Button {
						goBack()
					} label: {
						Label("Close", systemImage: "xmark")
					}
					.buttonStyle(.bordered)
					.buttonBorderShape(.capsule)
					.controlSize(.large)
					.padding(.bottom)
					#endif
				}
			}
		}
		.sheet(isPresented: $showingHelp) {
			ChannelsHelp()
				.presentationDetents([.large])
				#if !targetEnvironment(macCatalyst)
				.presentationDragIndicator(.visible)
				#endif
		}
		.safeAreaInset(edge: .bottom, alignment: .leading) {
			HStack {
				Button(action: {
					withAnimation {
						showingHelp = !showingHelp
					}
				}) {
					Image(systemName: !showingHelp ? "questionmark.circle" : "questionmark.circle.fill")
						.padding(.vertical, 5)
				}
				.tint(Color(UIColor.secondarySystemBackground))
				.foregroundColor(.accentColor)
				.buttonStyle(.borderedProminent)
				.buttonBorderShape(.circle)
				.accessibilityLabel(showingHelp ? String(localized: "Hide help", comment: "VoiceOver label for the help toggle button when help is showing") : String(localized: "Show help", comment: "VoiceOver label for the help toggle button when help is hidden"))
			}
			.controlSize(.regular)
			.padding(5)
		}
		.padding(.bottom, 5)
		.navigationTitle("Channels")
		.onAppear {
			normalizeDuplicateChannelsIfNeeded()
		}
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				ConnectedDevice(deviceConnected: accessoryManager.isConnected, name: accessoryManager.activeConnection?.device.shortName ?? "?")
			}
		}
	}
}

func firstMissingChannelIndex(_ indexes: [Int]) -> Int {
	let smallestIndex = 1
	if indexes.isEmpty { return smallestIndex }
	if smallestIndex <= indexes.count {
		for element in smallestIndex...indexes.count where !indexes.contains(element) {
			return element
		}
	}
	return indexes.count + 1
}

enum PositionPrecision: Int, CaseIterable, Identifiable {

	case two = 2
	case three = 3
	case four = 4
	case five = 5
	case six = 6
	case seven = 7
	case eight = 8
	case nine = 9
	case ten = 10
	case eleven = 11
	case twelve = 12
	case thirteen = 13
	case fourteen = 14
	case fifteen = 15
	case sixteen = 16
	case seventeen = 17
	case eightteen = 18
	case nineteen = 19
	case twenty = 20
	case twentyone = 21
	case twentytwo = 22
	case twentythree = 23
	case twentyfour = 24

	var id: Int { self.rawValue }

	var precisionMeters: Double {
		switch self {
		case .two:
			return 5976446.981252
		case .three:
			return 2988223.4850600003
		case .four:
			return 1494111.7369640006
		case .five:
			return 747055.8629159998
		case .six:
			return 373527.9258920002
		case .seven:
			return 186763.95738000044
		case .eight:
			return 93381.97312400135
		case .nine:
			return 46690.98099600022
		case .ten:
			return 23345.48493200123
		case .eleven:
			return 11672.736900000944
		case .twelve:
			return 5836.362884000802
		case .thirteen:
			return 2918.1758760007315
		case .fourteen:
			return 1459.0823719999053
		case .fifteen:
			return 729.5356200010741
		case .sixteen:
			return 364.7622440000765
		case .seventeen:
			return 182.37555600115968
		case .eightteen:
			return 91.1822120001193
		case .nineteen:
			return 45.58554000039009
		case .twenty:
			return 22.787204001316468
		case .twentyone:
			return 11.388036000988677
		case .twentytwo:
			return 5.688452000824781
		case .twentythree:
			return 2.8386600007428338
		case .twentyfour:
			return 1.413763999910884
		}
	}

	var description: String {
		let distanceFormatter = MKDistanceFormatter()
		return String.localizedStringWithFormat("Within %@".localized, String(distanceFormatter.string(fromDistance: precisionMeters)))
	}
}

private struct ChannelConfigSummaryRow: View {
	let summary: ChannelFrequencySummary

	var body: some View {
		HStack(spacing: 8) {
			Image(systemName: "antenna.radiowaves.left.and.right")
				.foregroundStyle(.secondary)
			Text(summary.regionName)
			Spacer(minLength: 8)
			Text("\(summary.frequencyText) · Slot \(summary.slotText)")
				.monospacedDigit()
		}
		.font(.caption)
		.foregroundStyle(.secondary)
		.listRowSeparator(.hidden)
		.accessibilityElement(children: .combine)
	}
}

private struct ChannelRow: View {
	let channel: ChannelEntity
	let sharesLocation: Bool

	private var title: String {
		if let name = channel.name, !name.isEmpty {
			return name
		}
		if channel.role == 1 {
			return "Primary Channel"
		}
		return "Channel \(channel.index)"
	}

	private var subtitle: String {
		if channel.role == 1 {
			return "Primary channel"
		}
		return "Channel \(channel.index)"
	}

	var body: some View {
		HStack(alignment: .center, spacing: 10) {
			CircleText(text: String(channel.index), color: .accentColor, circleSize: 45)
				.padding(.trailing, 5)
				.brightness(0.1)
			VStack(alignment: .leading, spacing: 3) {
				HStack(spacing: 6) {
					ChannelLock(channel: channel)
					Text(title)
						.font(.headline)
						.foregroundStyle(.primary)
				}
				Text(subtitle)
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			Spacer(minLength: 0)
			HStack(spacing: 8) {
				if sharesLocation {
					ChannelStatusIcon(
						systemImage: "location.fill",
						color: .green,
						accessibilityLabel: String(localized: "Position sharing", comment: "VoiceOver: this channel shares location")
					)
				}
				if channel.uplinkEnabled {
					ChannelStatusIcon(
						systemImage: "icloud.and.arrow.up",
						color: .blue,
						accessibilityLabel: String(localized: "MQTT uplink enabled", comment: "VoiceOver: this channel uplinks to MQTT")
					)
				}
				if channel.downlinkEnabled {
					ChannelStatusIcon(
						systemImage: "icloud.and.arrow.down",
						color: .blue,
						accessibilityLabel: String(localized: "MQTT downlink enabled", comment: "VoiceOver: this channel downlinks from MQTT")
					)
				}
			}
		}
		.padding(.vertical, 4)
		.accessibilityElement(children: .combine)
	}
}

private struct ChannelStatusIcon: View {
	let systemImage: String
	let color: Color
	let accessibilityLabel: String

	var body: some View {
		Image(systemName: systemImage)
			.font(.caption)
			.foregroundStyle(color)
			.accessibilityLabel(accessibilityLabel)
	}
}

// `ChannelFrequencySummary`, `LoRaChannelCalculator`, `RegionInfo`, and the
// `ModemPresets` bandwidth/name helpers moved to
// `Meshtastic/Helpers/LoRaChannelCalculator.swift` so the Mesh Beacons join
// enhancement can reuse the firmware-accurate slot math.
