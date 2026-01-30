//
//  LocationHistory.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 7/5/22.
//
import SwiftUI
import OSLog

struct PositionLog: View {
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.verticalSizeClass) var verticalSizeClass: UserInterfaceSizeClass?
	@Environment(\.horizontalSizeClass) var horizontalSizeClass: UserInterfaceSizeClass?
	var useGrid: Bool {
		let result = (verticalSizeClass == .regular || verticalSizeClass == .compact) && horizontalSizeClass == .compact
		return result
	}
	@State var isExporting = false
	@State var exportString = ""
	@ObservedObject var node: NodeInfoEntity
	@State private var isPresentingClearLogConfirm = false
	@State private var sortOrder = [KeyPathComparator(\PositionEntity.time)]

	var body: some View {
		VStack {
			if node.hasPositions {
				let localeDateFormat = DateFormatter.dateFormat(fromTemplate: "yyMMddjmma", options: 0, locale: Locale.current)
				let dateFormatString = (localeDateFormat ?? "MM/dd/YY j:mma").replacingOccurrences(of: ",", with: "")
				if UIDevice.current.userInterfaceIdiom == .pad && !useGrid || UIDevice.current.userInterfaceIdiom == .mac {
					// Add a table for mac and ipad
					let positions = node.positions?.reversed() as? [PositionEntity] ?? []
					Table(positions, sortOrder: $sortOrder) {
						TableColumn("Latitude") { position in
							Text(String(format: "%.5f", position.latitude ?? 0))
						}
						.width(min: 120)
						TableColumn("Longitude") { position in
							Text(String(format: "%.5f", position.longitude ?? 0))
						}
						.width(min: 120)
						TableColumn("Altitude") { position in
							let altitude = Measurement(value: Double(position.altitude), unit: UnitLength.meters)
							Text(String(altitude.formatted()))
						}
						TableColumn("Sats") { position in
							Text(String(position.satsInView))
						}
						TableColumn("Speed") { position in
							let speed = Measurement(value: Double(position.speed), unit: UnitSpeed.kilometersPerHour)
							Text(speed.formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0)))))
						}
						TableColumn("Heading") { position in
							let degrees = Angle.degrees(Double(position.heading))
							let heading = Measurement(value: degrees.degrees, unit: UnitAngle.degrees)
							Text(heading.formatted(.measurement(width: .narrow, numberFormatStyle: .number.precision(.fractionLength(0)))))
								.textSelection(.enabled)
						}
						TableColumn("SNR") { position in
							Text("\(String(format: "%.2f", position.snr)) dB")
						}
						TableColumn("Time Stamp") { position in
							Text(position.time?.formattedDate(format: dateFormatString) ?? "Unknown Age".localized)
						}
						.width(min: 180)
					}
					.textSelection(.enabled)
				} else {
					ScrollView {
						// Use a grid on iOS as a table only shows a single column
						let columns = [
							GridItem(spacing: 0.1),
							GridItem(spacing: 0.1),
							GridItem(.flexible(minimum: 35, maximum: 40), spacing: 0.1),
							GridItem(.flexible(minimum: 45, maximum: 50), spacing: 0.1),
							GridItem(spacing: 0)
						]
						LazyVGrid(columns: columns, alignment: .leading, spacing: 1) {
							GridRow {
								Text("Latitude")
									.font(.caption2)
									.fontWeight(.bold)
								Text("Longitude")
									.font(.caption2)
									.fontWeight(.bold)
								Text("Sats")
									.font(.caption2)
									.fontWeight(.bold)
								Text("Alt")
									.font(.caption2)
									.fontWeight(.bold)
								Text("Timestamp")
									.font(.caption2)
									.fontWeight(.bold)
							}
							if let positions = node.positions?.reversed() as? [PositionEntity] {
								ForEach(positions, id: \.self) { (mappin: PositionEntity) in
									let altitude = Measurement(value: Double(mappin.altitude), unit: UnitLength.meters)
									GridRow {
										Text(String(format: "%.5f", mappin.latitude ?? 0))
											.font(.caption2)
										Text(String(format: "%.5f", mappin.longitude ?? 0))
											.font(.caption2)
										Text(String(mappin.satsInView))
											.font(.caption2)
										Text(altitude.formatted())
											.font(.caption2)
										Text(mappin.time?.formattedDate(format: dateFormatString) ?? "Unknown Age".localized)
											.font(.caption2)
									}
								}
							}
						}
					}
					.padding(.leading)
				}
				HStack {
					Button(role: .destructive) {
						isPresentingClearLogConfirm = true
					} label: {
						Label("Clear Log", systemImage: "trash.fill")
					}
					.buttonStyle(.bordered)
					.buttonBorderShape(.capsule)
					.controlSize(.large)
					.padding(.bottom)
					.padding(.leading)
					.confirmationDialog(
						"Are you sure?",
						isPresented: $isPresentingClearLogConfirm,
						titleVisibility: .visible
					) {
						Button("Delete all positions?", role: .destructive) {
							Task {
								if await MeshPackets.shared.clearPositions(destNum: node.num) {
									Logger.services.info("Successfully Cleared Position Log")
								} else {
									Logger.services.error("Clear Position Log Failed")
								}
							}
						}
					}
					Button {
						exportString = positionToCsvFile(positions: node.positions!.array as? [PositionEntity] ?? [])
						isExporting = true
					} label: {
						Label("Save", systemImage: "square.and.arrow.down")
					}
					.buttonStyle(.bordered)
					.buttonBorderShape(.capsule)
					.controlSize(.large)
					.padding(.bottom)
					.padding(.trailing)
				}
				.fileExporter(
					isPresented: $isExporting,
					document: CsvDocument(emptyCsv: exportString),
					contentType: .commaSeparatedText,
					defaultFilename: String("\(node.user?.longName ?? "Node") Position Log"),
					onCompletion: { result in
						switch result {
						case .success:
							Logger.services.info("Position log download succeeded.")
							self.isExporting = false
						case .failure(let error):
							Logger.services.error("Position log download failed: \(error.localizedDescription, privacy: .public)")
						}
					}
				)

			} else {
				ContentUnavailableView("No Positions", systemImage: "mappin.slash")
			}
		}
		.navigationTitle("Position Log \(node.positions?.count ?? 0) Points")
		.navigationBarItems(
			trailing:
				ZStack {
					ConnectedDevice(deviceConnected: accessoryManager.isConnected, name: accessoryManager.activeConnection?.device.shortName ?? "?")

		})
	}
}
