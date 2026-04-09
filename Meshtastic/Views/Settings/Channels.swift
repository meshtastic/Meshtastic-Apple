//
//  Channels.swift
//  Meshtastic Apple
//
//  Copyright(c) Garth Vander Houwen 4/8/22.
//

import CoreData
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

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.dismiss) private var goBack
	@Environment(\.sizeCategory) var sizeCategory
	@Environment(\.colorScheme) private var colorScheme

	var node: NodeInfoEntity

	@State private var isEditingChannel = false
	@State private var selectedChannel: ChannelEntity?
	@State private var editContext: NSManagedObjectContext?
	@State private var showingHelp = false

	@FetchRequest private var channels: FetchedResults<ChannelEntity>

	init(node: NodeInfoEntity) {
		self.node = node
		_channels = FetchRequest(
			sortDescriptors: [NSSortDescriptor(keyPath: \ChannelEntity.index, ascending: true)],
			predicate: NSPredicate(format: "myInfoChannel.myNodeNum == %lld", node.num),
			animation: .default
		)
	}

	var body: some View {

		VStack {
			List {
				TipView(CreateChannelsTip(), arrowEdge: .bottom)
					.tipBackground(colorScheme == .dark ? Color(.systemBackground) : Color(.secondarySystemBackground))
					.listRowSeparator(.hidden)
				ForEach(channels) { channel in
					Button(action: { beginEditing(channel: channel) }) {
						VStack(alignment: .leading) {
							HStack {
								CircleText(text: String(channel.index), color: .accentColor, circleSize: 45)
									.padding(.trailing, 5)
									.brightness(0.1)
								VStack {
									HStack {
										ChannelLock(channel: channel)
										if channel.name?.isEmpty ?? true {
											if channel.role == 1 {
												Text(String("PrimaryChannel").camelCaseToWords()).font(.headline)
											} else {
												Text(String("Channel \(channel.index)").camelCaseToWords()).font(.headline)
											}
										} else {
											Text(String(channel.name ?? "Channel \(channel.index)").camelCaseToWords()).font(.headline)
										}
									}
								}
							}
						}
					}
				}
			}
			.sheet(isPresented: $isEditingChannel, onDismiss: cancelEditing) {
				#if targetEnvironment(macCatalyst)
				Text("Channel")
					.font(.largeTitle)
					.padding()
				#endif
				if let channel = selectedChannel {
					ChannelForm(channel: channel)
						.presentationDetents([.large])
						.presentationDragIndicator(.visible)
				}
				HStack {
					Button {
						saveChannel()
					} label: {
						Label("Save", systemImage: "square.and.arrow.down")
					}
					.disabled(!accessoryManager.isConnected)
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
			if channels.count < 8 {
				Button {
					addChannel()
				} label: {
					Label("Add Channel", systemImage: "plus.square")
				}
				.buttonStyle(.bordered)
				.buttonBorderShape(.capsule)
				.controlSize(.large)
				.padding()
			}
		}
		.sheet(isPresented: $showingHelp) {
			ChannelsHelp()
				.presentationDetents([.large])
				.presentationDragIndicator(.visible)
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
			}
			.controlSize(.regular)
			.padding(5)
		}
		.padding(.bottom, 5)
		.navigationTitle("Channels")
		.navigationBarItems(trailing:
		ZStack {
			ConnectedDevice(deviceConnected: accessoryManager.isConnected, name: accessoryManager.activeConnection?.device.shortName ?? "?")
		})
	}

	// MARK: - Editing helpers

	private func beginEditing(channel: ChannelEntity) {
		let childContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
		childContext.parent = context
		guard let channelInChild = childContext.object(with: channel.objectID) as? ChannelEntity else { return }
		editContext = childContext
		selectedChannel = channelInChild
		isEditingChannel = true
	}

	private func addChannel() {
		let channelIndexes = channels.map { Int($0.index) }
		let nextIndex = firstMissingChannelIndex(channelIndexes)
		let key = generateChannelKey(size: 16)

		let childContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
		childContext.parent = context

		let newChannel = ChannelEntity(context: childContext)
		newChannel.id = Int32(nextIndex)
		newChannel.index = Int32(nextIndex)
		newChannel.role = 2 // Secondary
		newChannel.name = ""
		newChannel.psk = Data(base64Encoded: key)
		newChannel.uplinkEnabled = false
		newChannel.downlinkEnabled = false
		newChannel.positionPrecision = 0

		if let myInfo = node.myInfo,
		   let myInfoInChild = childContext.object(with: myInfo.objectID) as? MyInfoEntity {
			newChannel.myInfoChannel = myInfoInChild
		}

		editContext = childContext
		selectedChannel = newChannel
		isEditingChannel = true
	}

	private func saveChannel() {
		guard let editCtx = editContext, let channel = selectedChannel else { return }

		let isNew = channel.objectID.isTemporaryID
		let channelIndex = channel.index
		let proto = channel.protoBuf

		if channel.role == 0 { // Disabled = delete existing channel
			if !isNew, let parentChannel = context.object(with: channel.objectID) as? ChannelEntity {
				for message in parentChannel.allPrivateMessages {
					context.delete(message)
				}
				let nodesFetch = NodeInfoEntity.fetchRequest()
				nodesFetch.predicate = NSPredicate(format: "channel == %d", channelIndex)
				let orphans = (try? context.fetch(nodesFetch)) ?? []
				for orphan in orphans {
					context.delete(orphan)
				}
				context.delete(parentChannel)
				do {
					try context.save()
					Logger.data.info("💾 Deleted Channel \(channelIndex)")
				} catch {
					context.rollback()
					let nsError = error as NSError
					Logger.data.error("Unresolved CoreData error deleting channel. Error: \(nsError, privacy: .public)")
				}
			}
			isEditingChannel = false
			return
		}

		do {
			try editCtx.save()
			try context.save()
			Logger.data.info("💾 Saved Channel: \(proto.settings.name, privacy: .public)")
		} catch {
			editCtx.rollback()
			let nsError = error as NSError
			Logger.data.error("Unresolved CoreData error saving channel. Error: \(nsError, privacy: .public)")
			return
		}

		Task {
			_ = try? await accessoryManager.saveChannel(channel: proto, fromUser: node.user!, toUser: node.user!)
			Task { @MainActor in
				isEditingChannel = false
			}
			accessoryManager.mqttManager.connectFromConfigSettings(node: node)
		}
	}

	private func cancelEditing() {
		selectedChannel = nil
		editContext = nil
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
