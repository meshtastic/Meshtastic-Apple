//
//  Settings.swift
//  MeshtasticApple
//
//  Copyright (c) Garth Vander Houwen 6/9/22.
//

import SwiftUI

enum SettingsSidebar: CaseIterable {
	case about
	case appSettings
	case routes
	case radioConfig
	case moduleConfig
	case meshLog
	case adminMessageLog
	var name: String {
	  switch self {
	  case .about:  
		  return "about.meshtastic".localized
	  case .appSettings:  
		  return "app.settings".localized
	  case .routes:  
		  return "routes".localized
	  case .radioConfig:
		  return "radio.configuration".localized
	  case .moduleConfig:
		  return "module.configuration".localized
	  case .meshLog:
		  return "mesh.log".localized
	  case .adminMessageLog:
		  return "admin.log".localized
	  }
	}
	var icon: String {
	  switch self {
	  case .about:
		  return "questionmark.app"
	  case .appSettings:
		  return "gearshape".localized
	  case .routes:
		  return "routes".localized
	  case .radioConfig:
		  return "flipphone".localized
	  case .moduleConfig:
		  return "module.configuration".localized
	  case .meshLog:
		  return "mesh.log".localized
	  case .adminMessageLog:
		  return "admin.log".localized
	  }
	}
}
extension SettingsSidebar: Identifiable {
  var id: Self { self }
}

@available(iOS 17.0, macOS 14.0, *)
struct Settings2: View {
	@State private var compactColumn = NavigationSplitViewColumn.detail
	@State private var columnVisibility = NavigationSplitViewVisibility.automatic
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@FetchRequest(sortDescriptors: [NSSortDescriptor(key: "user.longName", ascending: true)], animation: .default)
	private var nodes: FetchedResults<NodeInfoEntity>
	@State private var selectedNode: Int = 0
	@State private var preferredNodeNum: Int = 0
	@State private var selection: SettingsSidebar = .about

	enum SettingsContent {
		case appSettings
		case routes
		case shareChannels
		case userConfig
		case loraConfig
		case channelConfig
		case bluetoothConfig
		case deviceConfig
		case displayConfig
		case networkConfig
		case positionConfig
		case cannedMessagesConfig
		case detectionSensorConfig
		case externalNotificationConfig
		case mqttConfig
		case rangeTestConfig
		case ringtoneConfig
		case serialConfig
		case telemetryConfig
		case meshLog
		case adminMessageLog
		case about
	}
	var body: some View {
		NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $compactColumn) {
			
			List(SettingsSidebar.allCases) { item in
				switch(item) {
				case .about:
					NavigationLink { AboutMeshtastic() } label: {
						Image(systemName: item.icon)
							.symbolRenderingMode(.hierarchical)
						Text(item.name.localized)
					}
					.tag(item)
				case .appSettings:
					NavigationLink { AppSettings() } label: {
						Image(systemName: item.icon)
							.symbolRenderingMode(.hierarchical)
						Text(item.name.localized)
					}
					.tag(item)
				case .routes:
					NavigationLink {  Routes() } label: {
						Image(systemName: item.icon)
							.symbolRenderingMode(.hierarchical)
						Text(item.name.localized)
					}
					.tag(item)
				case .radioConfig:
					NavigationLink {  Routes() } label: {
						Image(systemName: item.icon)
							.symbolRenderingMode(.hierarchical)
						Text(item.name.localized)
					}
					.tag(item)
				case .moduleConfig:
					NavigationLink {  Routes() } label: {
						Image(systemName: item.icon)
							.symbolRenderingMode(.hierarchical)
						Text(item.name.localized)
					}
					.tag(item)
				case .meshLog:
					NavigationLink {  MeshLog() } label: {
						Image(systemName: item.icon)
							.symbolRenderingMode(.hierarchical)
						Text(item.name.localized)
					}
					.tag(item)
				case .adminMessageLog:
					NavigationLink {  AdminMessageList() } label: {
						Image(systemName: item.icon)
							.symbolRenderingMode(.hierarchical)
						Text(item.name.localized)
					}
					.tag(item)
				}
			}
			.listStyle(GroupedListStyle())
			.navigationTitle("settings")
			.navigationBarItems(leading: MeshtasticLogo())
		} content: {
			List {
				if selection == .routes {
					Text("Routes Bitechs")
				}
			}
		}
		detail: {
			Text("Detail")
			ContentUnavailableView("select.menu.item", systemImage: "gear")
		}
		.onChange(of: selection) { value in
			columnVisibility = .doubleColumn
			compactColumn = .sidebar

		}
	}
}
