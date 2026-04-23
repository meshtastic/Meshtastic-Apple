//
//  TAKModuleConfig.swift
//  Meshtastic
import SwiftUI
import CoreData
import OSLog
import MeshtasticProtobufs

struct TAKModuleConfig: View {
	@Environment(\.managedObjectContext) private var context
	@EnvironmentObject private var accessoryManager: AccessoryManager
	@Environment(\.dismiss) private var goBack

	let node: NodeInfoEntity?

	@State private var hasChanges = false
	@State private var team = Team.unspecifedColor.rawValue
	@State private var role = MemberRole.unspecifed.rawValue

	private var selectedTeam: Team {
		Team(rawValue: team) ?? .unspecifedColor
	}

	private var selectedRole: MemberRole {
		MemberRole(rawValue: role) ?? .unspecifed
	}

	private var deviceRole: DeviceRoles? {
		guard let role = node?.deviceConfig?.role ?? node?.user?.role else { return nil }
		return DeviceRoles(rawValue: Int(role))
	}

	var body: some View {
		Form {
			ConfigHeader(title: "TAK", config: \.takConfig, node: node, onAppear: setTAKValues)

			if accessoryManager.isConnected, node?.takConfig == nil {
				Section {
					HStack(spacing: 12) {
						ProgressView()
						Text("Loading TAK config from the node.")
							.foregroundColor(.secondary)
					}
				}
			}

			if let deviceRole, deviceRole != .tak && deviceRole != .takTracker {
				Section {
					Text("These settings only apply when the device role is TAK or TAK Tracker.")
						.font(.callout)
						.foregroundColor(.orange)
				}
			}

			Section(header: Text("Identity")) {
				VStack(alignment: .leading) {
					Picker("Team", selection: $team) {
						ForEach(Team.allCases, id: \.rawValue) { teamOption in
							Text(teamTitle(teamOption)).tag(teamOption.rawValue)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					Text(teamHelpText(selectedTeam))
						.foregroundColor(.gray)
						.font(.callout)
				}

				VStack(alignment: .leading) {
					Picker("Role", selection: $role) {
						ForEach(MemberRole.allCases, id: \.rawValue) { roleOption in
							Text(roleTitle(roleOption)).tag(roleOption.rawValue)
						}
					}
					.pickerStyle(DefaultPickerStyle())
					Text(roleHelpText(selectedRole))
						.foregroundColor(.gray)
						.font(.callout)
				}
			}

			Section {
				Text("These values are included in TAK position reports. Leave either setting at Default to let firmware use Cyan and Team Member.")
					.foregroundColor(.gray)
					.font(.callout)
			}
		}
		.disabled(!accessoryManager.isConnected || node?.takConfig == nil)
		.safeAreaInset(edge: .bottom, alignment: .center) {
			HStack(spacing: 0) {
				SaveConfigButton(node: node, hasChanges: $hasChanges) {
					guard let connectedNode = getNodeInfo(id: accessoryManager.activeDeviceNum ?? -1, context: context),
						  let fromUser = connectedNode.user,
						  let toUser = node?.user else {
						return
					}

					var config = ModuleConfig.TAKConfig()
					config.team = selectedTeam
					config.role = selectedRole

					Task {
						_ = try await accessoryManager.saveTAKModuleConfig(config: config, fromUser: fromUser, toUser: toUser)
						Task { @MainActor in
							hasChanges = false
							goBack()
						}
					}
				}
			}
		}
		.navigationTitle("TAK Config")
		.navigationBarItems(
			trailing: ZStack {
				ConnectedDevice(
					deviceConnected: accessoryManager.isConnected,
					name: accessoryManager.activeConnection?.device.shortName ?? "?"
				)
			}
		)
		.onAppear {
			// Need to request a TAKModuleConfig from the connected node before allowing changes.
			if let deviceNum = accessoryManager.activeDeviceNum,
			   let node,
			   node.num == deviceNum,
			   node.takConfig == nil {
				let connectedNode = getNodeInfo(id: deviceNum, context: context)
				if let connectedNode {
					Task {
						do {
							Logger.mesh.info("⚙️ Empty TAK module config requesting from connected node")
							try await accessoryManager.requestTAKModuleConfig(fromUser: connectedNode.user!, toUser: node.user!)
						} catch {
							Logger.mesh.error("🚨 TAK module config request failed: \(error.localizedDescription)")
						}
					}
				}
			}
		}
		.onFirstAppear {
			if let deviceNum = accessoryManager.activeDeviceNum, let node {
				let connectedNode = getNodeInfo(id: deviceNum, context: context)
				if let connectedNode, node.num != deviceNum {
					if UserDefaults.enableAdministration {
						let expiration = node.sessionExpiration ?? Date()
						if expiration < Date() || node.takConfig == nil {
							Task {
								do {
									Logger.mesh.info("⚙️ Empty or expired TAK module config requesting via PKI admin")
									try await accessoryManager.requestTAKModuleConfig(fromUser: connectedNode.user!, toUser: node.user!)
								} catch {
									Logger.mesh.info("🚨 TAK module config request failed: \(error.localizedDescription)")
								}
							}
						}
					} else {
						Logger.mesh.info("☠️ Using insecure legacy admin that is no longer supported, please upgrade your firmware.")
					}
				}
			}
		}
		.onChange(of: team) { _, newTeam in
			if newTeam != Int(node?.takConfig?.team ?? Int32(Team.unspecifedColor.rawValue)) {
				hasChanges = true
			}
		}
		.onChange(of: role) { _, newRole in
			if newRole != Int(node?.takConfig?.role ?? Int32(MemberRole.unspecifed.rawValue)) {
				hasChanges = true
			}
		}
	}

	private func setTAKValues() {
		team = Int(node?.takConfig?.team ?? Int32(Team.unspecifedColor.rawValue))
		role = Int(node?.takConfig?.role ?? Int32(MemberRole.unspecifed.rawValue))
		hasChanges = false
	}

	private func teamTitle(_ team: Team) -> String {
		switch team {
		case .unspecifedColor:
			return "Default (Cyan)"
		case .white:
			return "White"
		case .yellow:
			return "Yellow"
		case .orange:
			return "Orange"
		case .magenta:
			return "Magenta"
		case .red:
			return "Red"
		case .maroon:
			return "Maroon"
		case .purple:
			return "Purple"
		case .darkBlue:
			return "Dark Blue"
		case .blue:
			return "Blue"
		case .cyan:
			return "Cyan"
		case .teal:
			return "Teal"
		case .green:
			return "Green"
		case .darkGreen:
			return "Dark Green"
		case .brown:
			return "Brown"
		case .UNRECOGNIZED:
			return "Unknown"
		}
	}

	private func roleTitle(_ role: MemberRole) -> String {
		switch role {
		case .unspecifed:
			return "Default (Team Member)"
		case .teamMember:
			return "Team Member"
		case .teamLead:
			return "Team Lead"
		case .hq:
			return "HQ"
		case .sniper:
			return "Sniper"
		case .medic:
			return "Medic"
		case .forwardObserver:
			return "Forward Observer"
		case .rto:
			return "RTO"
		case .k9:
			return "K9"
		case .UNRECOGNIZED:
			return "Unknown"
		}
	}

	private func teamHelpText(_ team: Team) -> String {
		switch team {
		case .unspecifedColor:
			return "Default uses Cyan."
		case .UNRECOGNIZED:
			return "Unknown team color."
		default:
			return "Shown to TAK clients as the \(teamTitle(team)) team color."
		}
	}

	private func roleHelpText(_ role: MemberRole) -> String {
		switch role {
		case .unspecifed:
			return "Default uses Team Member."
		case .UNRECOGNIZED:
			return "Unknown TAK role."
		default:
			return "Shown to TAK clients as the \(roleTitle(role)) role."
		}
	}
}

#Preview {
	let context = PersistenceController.preview.container.viewContext
	return TAKModuleConfig(node: nil)
		.environmentObject(AccessoryManager.shared)
		.environment(\.managedObjectContext, context)
}
