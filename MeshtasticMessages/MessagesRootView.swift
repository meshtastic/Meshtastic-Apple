//
//  MessagesRootView.swift
//  MeshtasticMessages
//

import SwiftUI

struct MessagesRootView: View {
	@ObservedObject var viewModel: MessagesViewModel

	var body: some View {
		Group {
			if let payload = viewModel.selectedPayload {
				ReceivedShareView(payload: payload, viewModel: viewModel)
			} else {
				TabView {
					ContactShareView(viewModel: viewModel)
						.tabItem { Label("Contact", systemImage: "person.crop.circle.badge.plus") }
					ChannelShareView(viewModel: viewModel)
						.tabItem { Label("Channels", systemImage: "antenna.radiowaves.left.and.right") }
					StickerShareView(viewModel: viewModel)
						.tabItem { Label("Stickers", systemImage: "face.smiling") }
				}
				.tint(.green)
			}
		}
		.alert(
			"Couldn't Share",
			isPresented: Binding(
				get: { viewModel.errorMessage != nil },
				set: { if !$0 { viewModel.errorMessage = nil } }
			)
		) {
			Button("OK", role: .cancel) { viewModel.errorMessage = nil }
		} message: {
			Text(viewModel.errorMessage ?? "")
		}
	}
}

private struct RecentRadioHeader: View {
	let snapshot: MeshShareSnapshot

	var body: some View {
		HStack(spacing: 12) {
			Image(systemName: "antenna.radiowaves.left.and.right.circle.fill")
				.font(.largeTitle)
				.foregroundStyle(.green)
			VStack(alignment: .leading, spacing: 2) {
				Text(snapshot.radioLongName.isEmpty ? "Recent radio" : snapshot.radioLongName)
					.font(.headline)
				Text(snapshot.radioShortName)
					.font(.caption.monospaced())
					.foregroundStyle(.secondary)
			}
			Spacer()
		}
	}
}

private struct ContactShareView: View {
	@ObservedObject var viewModel: MessagesViewModel

	var body: some View {
		ScrollView {
			VStack(spacing: 16) {
				if let snapshot = viewModel.snapshot {
					RecentRadioHeader(snapshot: snapshot)
					.padding(.top)
				Image(uiImage: bundledImage(named: "chirpy"))
					.resizable()
					.scaledToFit()
					.frame(height: 100)
				Text("Swap mesh contacts")
					.font(.title2.bold())
				Text("Your public identity and key come from the most recently connected radio. The recipient can add you and send theirs back.")
					.font(.subheadline)
					.multilineTextAlignment(.center)
					.foregroundStyle(.secondary)
				if snapshot.isStale() {
					Label("This snapshot is over 30 days old.", systemImage: "clock.badge.exclamationmark")
						.font(.caption)
						.foregroundStyle(.orange)
				}
				Button(action: viewModel.sendContact) {
					Label("Send Contact Exchange", systemImage: "arrow.left.arrow.right.circle.fill")
						.frame(maxWidth: .infinity)
				}
				.buttonStyle(.borderedProminent)
				.tint(.green)
				.controlSize(.large)
				} else {
					ContentUnavailableView(
						"No Recent Radio",
						systemImage: "antenna.radiowaves.left.and.right.slash",
						description: Text("Open Meshtastic and connect once. You can share later while disconnected.")
					)
					.padding(.top, 30)
				}
			}
			.padding(.horizontal)
		}
	}
}

private func bundledImage(named name: String) -> UIImage {
	guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
		  let image = UIImage(contentsOfFile: url.path) else {
		return UIImage(systemName: "antenna.radiowaves.left.and.right.circle.fill") ?? UIImage()
	}
	return image
}

private struct ChannelShareView: View {
	@ObservedObject var viewModel: MessagesViewModel
	@State private var selected: Set<Int32> = []
	@State private var mode: MeshChannelImportMode = .replace
	@State private var initializedSnapshot: Date?

	var body: some View {
		NavigationStack {
			Group {
				if let snapshot = viewModel.snapshot {
					List {
						Section {
							RecentRadioHeader(snapshot: snapshot)
						}
						Section("Import behavior") {
							Picker("Mode", selection: $mode) {
								Text("Replace").tag(MeshChannelImportMode.replace)
								Text("Add").tag(MeshChannelImportMode.add)
							}
							.pickerStyle(.segmented)
							Text(mode == .replace
								 ? "Replace matches the Meshtastic app default and includes the radio's LoRa settings."
								 : "Add keeps the recipient's LoRa settings and adds the selected channels.")
								.font(.caption)
								.foregroundStyle(.secondary)
						}
						Section("Channels") {
							ForEach(snapshot.channels) { channel in
								Button {
									if selected.contains(channel.index) {
										selected.remove(channel.index)
									} else {
										selected.insert(channel.index)
									}
								} label: {
									HStack {
										Image(systemName: selected.contains(channel.index) ? "checkmark.circle.fill" : "circle")
											.foregroundStyle(selected.contains(channel.index) ? .green : .secondary)
										Text(channel.name)
											.foregroundStyle(.primary)
										Spacer()
										if channel.isEncrypted {
											Image(systemName: "lock.fill")
												.foregroundStyle(.orange)
												.accessibilityLabel("Encrypted")
										}
									}
								}
							}
						}
						Section {
							Button {
								viewModel.sendChannels(selected, mode)
							} label: {
								Label(
									mode == .replace ? "Send Replace Card" : "Send Add Card",
									systemImage: "paperplane.fill"
								)
								.frame(maxWidth: .infinity)
							}
							.buttonStyle(.borderedProminent)
							.tint(.green)
							.disabled(selected.isEmpty)
						} footer: {
							Text("Encrypted channels include their secret key. Only send them to people you trust.")
						}
					}
					.onAppear {
						resetSelection(for: snapshot)
					}
					.onChange(of: snapshot.refreshedAt) {
						resetSelection(for: snapshot)
					}
				} else {
					ContentUnavailableView(
						"No Recent Radio",
						systemImage: "antenna.radiowaves.left.and.right.slash",
						description: Text("Open Meshtastic and connect once. You can share later while disconnected.")
					)
				}
			}
			.navigationTitle("Share Channels")
			.navigationBarTitleDisplayMode(.inline)
		}
	}

	private func resetSelection(for snapshot: MeshShareSnapshot) {
		guard initializedSnapshot != snapshot.refreshedAt else {
			return
		}
		selected = MeshChannelSelection(snapshot: snapshot).defaultSelectedIndexes
		mode = .replace
		initializedSnapshot = snapshot.refreshedAt
	}
}

private struct StickerShareView: View {
	@ObservedObject var viewModel: MessagesViewModel

	private let stickers = [
		("chirpy", "Chirpy"),
		("mesh-logo", "Meshtastic logo"),
		("mesh-powered", "Meshtastic Powered")
	]

	var body: some View {
		ScrollView {
			LazyVGrid(columns: [GridItem(.adaptive(minimum: 92))], spacing: 14) {
				ForEach(stickers, id: \.0) { sticker in
					Button {
						viewModel.sendSticker(sticker.0, sticker.1)
					} label: {
						VStack(spacing: 6) {
							Image(uiImage: bundledImage(named: sticker.0))
								.resizable()
								.scaledToFit()
								.frame(height: 78)
							Text(sticker.1)
								.font(.caption2)
								.foregroundStyle(.primary)
								.lineLimit(1)
						}
					}
					.buttonStyle(.plain)
				}
			}
			.padding()
		}
	}
}

private struct ReceivedShareView: View {
	let payload: MessagesViewModel.SelectedPayload
	@ObservedObject var viewModel: MessagesViewModel

	var body: some View {
		VStack(spacing: 18) {
			Image(systemName: icon)
				.font(.system(size: 54))
				.foregroundStyle(.green)
			Text(title)
				.font(.title2.bold())
			Text(detail)
				.multilineTextAlignment(.center)
				.foregroundStyle(.secondary)
			switch payload {
			case .contact(let url, let exchangeRequested):
				if exchangeRequested {
					Button {
						viewModel.addAndReply(url)
					} label: {
						Label("Add & Reply with Mine", systemImage: "arrow.left.arrow.right.circle.fill")
							.frame(maxWidth: .infinity)
					}
					.buttonStyle(.borderedProminent)
					.tint(.green)
					.disabled(viewModel.snapshot == nil)
					Button {
						viewModel.openInApp(url)
					} label: {
						Label("Just Add Contact", systemImage: "person.crop.circle.badge.plus")
					}
					.buttonStyle(.bordered)
				} else {
					Button {
						viewModel.openInApp(url)
					} label: {
						Label("Add Contact", systemImage: "person.crop.circle.badge.plus")
							.frame(maxWidth: .infinity)
					}
					.buttonStyle(.borderedProminent)
					.tint(.green)
				}
			case .channels(let url):
				Button {
					viewModel.openInApp(url)
				} label: {
					Label("Review in Meshtastic", systemImage: "square.and.arrow.down")
						.frame(maxWidth: .infinity)
				}
				.buttonStyle(.borderedProminent)
				.tint(.green)
			}
		}
		.padding()
	}

	private var icon: String {
		switch payload {
		case .contact:
			return "person.2.circle.fill"
		case .channels:
			return "antenna.radiowaves.left.and.right.circle.fill"
		}
	}

	private var title: String {
		switch payload {
		case .contact(_, let exchangeRequested):
			return exchangeRequested ? "Contact exchange" : "Mesh contact"
		case .channels:
			return "Shared channels"
		}
	}

	private var detail: String {
		switch payload {
		case .contact(_, let exchangeRequested):
			if exchangeRequested {
				return "Add their public identity to your radio, then put yours in the same conversation."
			}
			return "Add their public identity to your radio."
		case .channels:
			return "Review the selected encrypted channels and choose whether to replace or add them in Meshtastic."
		}
	}
}
