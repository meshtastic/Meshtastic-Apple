import Foundation
import Combine
import SwiftUI
import SwiftProtobuf
import MapKit
import DatadogCore
import OSLog
import SwiftData

struct AppSettings: View {
	private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
	@EnvironmentObject var accessoryManager: AccessoryManager
	@State var totalDownloadedTileSize = ""
	@State private var isPresentingCoreDataResetConfirm = false
	@State private var isPresentingDeleteMapTilesConfirm = false
	@State private var isPresentingAppIconSheet = false
	@State private var purgeStaleNodes: Bool = false
	@State private var showAutoConnect: Bool = false
	@AppStorage("purgeStaleNodeDays") private var  purgeStaleNodeDays: Double = 0
	@AppStorage("environmentEnableWeatherKit") private var  environmentEnableWeatherKit: Bool = true
	@AppStorage("enableAdministration") private var  enableAdministration: Bool = false
	@AppStorage("usageDataAndCrashReporting") private var usageDataAndCrashReporting: Bool = true
	// Node Layout Preferences
	@AppStorage("nodeListDensity") private var nodeListDensity: NodeListDensity = .standard
	@AppStorage(NodeListPreferences.shouldShowLocation.rawValue) private var shouldShowLocation = true
	@AppStorage(NodeListPreferences.shouldShowPower.rawValue) private var shouldShowPower = true
	@AppStorage(NodeListPreferences.shouldShowTelemetry.rawValue) private var shouldShowTelemetry = true
	@AppStorage(NodeListPreferences.shouldShowLastHeard.rawValue) private var shouldShowLastHeard = true
	@AppStorage(NodeListPreferences.lastHeardIsRelative.rawValue) private var lastHeardIsRelative = false
	@AppStorage(NodeListPreferences.shouldShowRole.rawValue) private var shouldShowRole = true
	@AppStorage(NodeListPreferences.shouldShowChannel.rawValue) private var shouldShowChannel = true
	@AppStorage(NodeListPreferences.shouldShowHops.rawValue) private var shouldShowHops = true
	@AppStorage(NodeListPreferences.shouldShowSignal.rawValue) private var shouldShowSignal = true
	@AppStorage("participateInDistributedTranslations") private var participateInDistributedTranslations = true

	let autoconnectBinding = Binding<Bool>(get: {
		return UserDefaults.autoconnectOnDiscovery
	}, set: { newValue in
		UserDefaults.autoconnectOnDiscovery = newValue
	})
	var body: some View {
		VStack {
			Form {
				Section(header: Text("App Settings")) {
					Button("Open Settings", systemImage: "gear") {
						// Get the settings URL and open it
						if let url = URL(string: UIApplication.openSettingsURLString) {
							UIApplication.shared.open(url)
						}
					}
					Toggle(isOn: $enableAdministration) {
						Label("Administration", systemImage: "gearshape.2")
					}
					.tint(.accentColor)
					Text("PKI based node administration, requires firmware version 2.5+")
						.foregroundStyle(.secondary)
						.font(.caption)
					Toggle(isOn: $usageDataAndCrashReporting) {
						Label("Usage and Crash Data", systemImage: "pencil.and.list.clipboard")
					}
					.tint(.accentColor)
					Text("Provide anonymous usage statistics and crash reports.")
						.foregroundStyle(.secondary)
						.font(.caption)
					if showAutoConnect {
						Toggle(isOn: autoconnectBinding) {
							Label("Automatically Connect", systemImage: "app.connected.to.app.below.fill")
						}
						.tint(.accentColor)
					}
#if targetEnvironment(macCatalyst)
					// App Icon Picker is disabled on macOS Catalyst
#else
					Button {
						isPresentingAppIconSheet.toggle()
					} label: {
						Label("App Icon", systemImage: "app")
					}
					.sheet(isPresented: $isPresentingAppIconSheet) {
						AppIconPicker(isPresenting: self.$isPresentingAppIconSheet)
							.presentationDetents([.medium])
					}
#endif
				}
				Section(header: Text("Node Layout")) {
					List {
						Picker("Node List Density", selection: $nodeListDensity.animation()) {
							ForEach(NodeListDensity.allCases) { item in
								Text(item.description).tag(item)
							}
						}
						.pickerStyle(.segmented)
						if nodeListDensity == .compact {
							Toggle(isOn: $shouldShowPower) {
								Text("Power")
							}
							Toggle(isOn: $shouldShowLastHeard.animation()) {
								Text("Last Heard Time")
							}
							Toggle(isOn: $lastHeardIsRelative) {
								Text("Relative Last Heard Time")
							}
							.disabled(!shouldShowLastHeard)
							Toggle(isOn: $shouldShowLocation) {
								Text("Distance and Bearing")
							}
							Toggle(isOn: $shouldShowHops) {
								Text("Hops Away")
							}
							Toggle(isOn: $shouldShowSignal) {
								Text("Signal (Direct Only)")
							}
							Toggle(isOn: $shouldShowChannel) {
								Text("Channel")
							}
							Toggle(isOn: $shouldShowRole) {
								Text("Device Role")
							}
							Toggle(isOn: $shouldShowTelemetry) {
								Text("Log Icons")
							}
						}
						if nodeListDensity == .standard {
							Text("The Complete layout displays all available node data. Fields with no data are automatically hidden.")
								.font(.footnote)
								.foregroundStyle(.secondary)
						}
						BuildTestNode(nodeListDensity: $nodeListDensity)
					}
				}
				Section(header: Text("Environment")) {
					VStack(alignment: .leading) {
						Toggle(isOn: $environmentEnableWeatherKit) {
							Label("Weather Conditions", systemImage: "cloud.sun")
						}
						.tint(.accentColor)
					}
				}
				Section(header: Text("App Data")) {
					Toggle(isOn: $purgeStaleNodes ) {
						Label {
							Text("Clear Stale Nodes")
						} icon: {
							Image(systemName: "list.bullet.circle")
						}
					}
					.onFirstAppear {
						purgeStaleNodes = purgeStaleNodeDays > 0
						Logger.services.info("ℹ️ Purge Stale Nodes toggle initialized to \(purgeStaleNodes)")
#if DEBUG
						showAutoConnect = true
#else
						if Bundle.main.isTestFlight {
							showAutoConnect = true
						}
#endif
					}
					.onChange(of: usageDataAndCrashReporting) { _, newUsageDataAndCrashReporting in
						if !newUsageDataAndCrashReporting {
							Datadog.set(trackingConsent: .notGranted)
						}
					}
					.onChange(of: purgeStaleNodes) { _, newValue in
						purgeStaleNodeDays = purgeStaleNodeDays > 0 ? purgeStaleNodeDays : 7
						purgeStaleNodeDays = newValue ? purgeStaleNodeDays : 0
						Logger.services.info("ℹ️ Purge Stale Nodes changed to \(purgeStaleNodeDays)")
					}
					.tint(.accentColor)

					.listRowSeparator(purgeStaleNodes ? .hidden : .visible)
					if purgeStaleNodes {
						VStack(alignment: .leading) {
							Text(String(localized: "After \(Int(purgeStaleNodeDays)) Days"))
							Slider(value: $purgeStaleNodeDays, in: 1...180, step: 1) {
							} minimumValueLabel: {
								Text("1")
							} maximumValueLabel: {
								Text("180")
							}
						}
						Text("Favorited and ignored nodes are always retained. Other nodes are cleared from the app database on the schedule set by the user. (Nodes with PKC keys are always retained for at least 7 days.) This feature only purges nodes from the app that are not stored in the device node database.")
							.foregroundStyle(.secondary)
							.font(idiom == .phone ? .caption : .callout)
					}
					Button {
						isPresentingCoreDataResetConfirm = true
					} label: {
						Label("Clear App Data", systemImage: "trash")
							.foregroundColor(.red)
					}
					.confirmationDialog(
						"Are you sure?",
						isPresented: $isPresentingCoreDataResetConfirm,
						titleVisibility: .visible
					) {
						Button("Erase all app data?", role: .destructive) {
							Task {
								try await accessoryManager.disconnect()
								
								/// Clear translation cache
								await TranslationCache.shared.clearAll()
								await DocTranslationService.shared.clearUIStringCache()
								
								/// Delete any database backups too
								if var url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
									url = url.appendingPathComponent("backup").appendingPathComponent(String(UserDefaults.preferredPeripheralNum))
									do {
										try FileManager.default.removeItem(at: url.appendingPathComponent("Meshtastic.sqlite"))
										/// Delete -shm file
										do {
											try FileManager.default.removeItem(at: url.appendingPathComponent("Meshtastic.sqlite-wal"))
											do {
												try FileManager.default.removeItem(at: url.appendingPathComponent("Meshtastic.sqlite-shm"))
											} catch {
												Logger.services.error("🗄 Error Deleting Meshtastic.sqlite-shm file \(error, privacy: .public)")
											}
										} catch {
											Logger.services.error("🗄 Error Deleting Meshtastic.sqlite-wal file \(error, privacy: .public)")
										}
									} catch {
										Logger.services.error("🗄 Error Deleting Meshtastic.sqlite file \(error, privacy: .public)")
									}
								}
								await MeshPackets.shared.flushDebouncedSaves()
								await MeshPackets.shared.clearDatabase(includeRoutes: true)
								MeshPackets.recreateShared()
								clearNotifications()
							}
						}
					}
					Button {
						UserDefaults.standard.reset()
					} label: {
						Label("Reset App Settings", systemImage: "arrow.counterclockwise.circle")
							.foregroundColor(.red)
					}
				}
				Section(header: Text("Documentation Translations")) {
					Toggle(isOn: $participateInDistributedTranslations) {
						Label("Participate in Distributed Translations", systemImage: "globe")
					}
					.tint(.accentColor)
					Text("Upload on-device translated documentation to help improve translations for the community. Translated docs are shared anonymously so other users get instant translations without needing on-device models.")
						.foregroundStyle(.secondary)
						.font(idiom == .phone ? .caption : .callout)
				}
			}
		}
		.navigationTitle("App Settings")
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				ConnectedDevice(deviceConnected: accessoryManager.isConnected, name: accessoryManager.activeConnection?.device.shortName ?? "?")
			}
		}
	}
}

struct BuildTestNode: View {
	@Environment(\.modelContext) private var context
	@Binding var nodeListDensity: NodeListDensity
	@State private var previewNode: BuildTestNodeSnapshot?
	
	init(nodeListDensity: Binding<NodeListDensity>) {
		self._nodeListDensity = nodeListDensity
	}

	var body: some View {
		VStack {
			if let previewNode {
				switch nodeListDensity {
				case .standard:
					BuildTestNodeStandardRow(node: previewNode)
				case .compact:
					BuildTestNodeCompactRow(node: previewNode)
				}
			}
		}
		.task {
			loadPreviewNode()
		}
	}

	@MainActor
	private func loadPreviewNode() {
		var descriptor = FetchDescriptor<NodeInfoEntity>(
			sortBy: [SortDescriptor(\NodeInfoEntity.lastHeard, order: .reverse)]
		)
		descriptor.fetchLimit = 1
		guard let exampleNode = try? context.fetch(descriptor).first else {
			previewNode = nil
			return
		}
		previewNode = BuildTestNodeSnapshot(node: exampleNode)
	}
}

private struct BuildTestNodeSnapshot {
	let shortName: String
	let longName: String
	let isFavorite: Bool
	let isOnline: Bool
	let lastHeardText: String
	let roleName: String
	let roleSystemName: String
	let isUnmonitored: Bool
	let isStoreForwardRouter: Bool
	let viaMqtt: Bool
	let channel: Int
	let hopsAway: Int
	let snr: Float
	let keyStatusImage: String
	let keyStatusColor: Color

	init(node: NodeInfoEntity) {
		let role = DeviceRoles(rawValue: Int(node.user?.role ?? 0))
		shortName = node.user?.shortName ?? "?"
		longName = node.user?.longName?.addingVariationSelectors ?? "Unknown".localized
		isFavorite = node.favorite
		isOnline = node.isOnline
		lastHeardText = node.lastHeard?.formatted(date: .numeric, time: .shortened) ?? "Unknown Age".localized
		roleName = role?.name ?? "Unknown".localized
		roleSystemName = role?.systemName ?? "figure"
		isUnmonitored = node.user?.unmessagable ?? false
		isStoreForwardRouter = node.storeForwardConfig?.isRouter ?? false
		viaMqtt = node.viaMqtt
		channel = Int(node.channel)
		hopsAway = Int(node.hopsAway)
		snr = node.snr

		if node.user?.pkiEncrypted ?? false {
			if node.user?.keyMatch ?? false {
				keyStatusImage = "lock.fill"
				keyStatusColor = .green
			} else {
				keyStatusImage = "key.slash"
				keyStatusColor = .red
			}
		} else {
			keyStatusImage = "lock.open.fill"
			keyStatusColor = .yellow
		}
	}
}

private struct BuildTestNodeStandardRow: View {
	let node: BuildTestNodeSnapshot
	private var modemPreset: ModemPresets { ModemPresets(rawValue: UserDefaults.modemPreset) ?? .longFast }

	var body: some View {
		LazyVStack(alignment: .leading) {
			HStack {
				VStack(alignment: .center) {
					CircleText(text: node.shortName, color: Color(UIColor(hex: 0x76A5AF)), circleSize: 70)
						.padding(.trailing, 5)
				}
				VStack(alignment: .leading) {
					HStack {
						IconAndText(systemName: node.keyStatusImage,
									imageColor: node.keyStatusColor,
									text: node.longName,
									textColor: .primary)
						if node.isFavorite {
							Spacer()
							Image(systemName: "star.fill")
								.symbolRenderingMode(.multicolor)
						}
					}
					IconAndText(systemName: "antenna.radiowaves.left.and.right.circle.fill",
								imageColor: .green,
								text: "Connected".localized)
					IconAndText(systemName: node.isOnline ? "checkmark.circle.fill" : "moon.circle.fill",
								imageColor: node.isOnline ? .green : .orange,
								text: node.lastHeardText)
					IconAndText(systemName: node.roleSystemName,
								text: "Role: \(node.roleName)")
					if node.isUnmonitored {
						IconAndText(systemName: "iphone.slash",
									renderingMode: .multicolor,
									text: "Unmonitored")
					}
					if node.isStoreForwardRouter {
						IconAndText(systemName: "envelope.arrow.triangle.branch",
									renderingMode: .multicolor,
									text: "Store & Forward".localized)
					}
					HStack {
						if node.channel > 0 {
							IconAndText(systemName: "\(node.channel).circle.fill", text: "Channel")
						}
						if node.viaMqtt {
							IconAndText(systemName: "dot.radiowaves.up.forward",
										renderingMode: .multicolor,
										text: "MQTT")
						}
					}
					if node.hopsAway > 0 {
						HStack {
							IconAndText(systemName: "hare", text: "Hops Away:")
							Image(systemName: "\(node.hopsAway).square")
								.font(.title2)
						}
					} else if node.snr != 0 && !node.viaMqtt {
						LoRaSignalStrengthMeter(snr: node.snr, rssi: 0, preset: modemPreset, compact: true)
							.padding(.top, 15)
					}
				}
			}
		}
	}
}

private struct BuildTestNodeCompactRow: View {
	let node: BuildTestNodeSnapshot

	var body: some View {
		LazyVStack(alignment: .leading) {
			HStack {
				VStack(alignment: .center) {
					CircleText(text: node.shortName, color: Color(UIColor(hex: 0x76A5AF)), circleSize: 42)
						.padding(.trailing, 5)
				}
				VStack(alignment: .leading, spacing: 2) {
					HStack(alignment: .firstTextBaseline) {
						IconAndText(systemName: node.keyStatusImage,
									imageColor: node.keyStatusColor,
									text: node.longName,
									textColor: .primary)
						if node.isFavorite {
							Spacer()
							Image(systemName: "star.fill")
								.symbolRenderingMode(.multicolor)
						}
					}
					IconAndText(systemName: node.isOnline ? "checkmark.circle.fill" : "moon.circle.fill",
								imageColor: node.isOnline ? .green : .orange,
								text: node.lastHeardText)
					HStack(alignment: .center, spacing: 6) {
						if node.hopsAway > 0 {
							DefaultIconCompact(systemName: "\(node.hopsAway).square")
						} else if node.snr != 0 && !node.viaMqtt {
							DefaultIconCompact(systemName: "dot.radiowaves.left.and.right")
						}
						if node.channel > 0 {
							Divider().frame(height: 15)
							DefaultIconCompact(systemName: "\(node.channel).circle.fill")
						}
						Divider().frame(height: 15)
						DefaultIconCompact(systemName: node.roleSystemName)
						if node.isUnmonitored {
							DefaultIconCompact(systemName: "iphone.slash")
						}
						if node.isStoreForwardRouter {
							DefaultIconCompact(systemName: "envelope.arrow.triangle.branch")
						}
						if node.viaMqtt {
							DefaultIconCompact(systemName: "dot.radiowaves.up.forward")
						}
					}
					.padding(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 0))
				}
				.frame(maxWidth: .infinity, alignment: .leading)
			}
		}
		.padding(.top, 2)
		.padding(.bottom, 2)
	}
}
