//
//  MQTTTopicFinder.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/11/26.
//

import CoreLocation
import MeshtasticProtobufs
import SwiftUI

/// Listens to the broker for a minute and lists the root topics heard near the user: the geocoded
/// region, country, state and city ladder and the community roots serving the area, with live node
/// counts, then every other root in reach, then a typed one. Picking a row fills the form's root
/// field; nothing reaches the radio until Save.
struct MQTTTopicFinder: View {
	@Binding var config: ModuleConfig.MQTTConfig
	let node: NodeInfoEntity?
	/// False for snapshots and previews: no socket, no geocoder.
	var autoStart = true
	@StateObject private var sampler: MqttTopicSampler
	@Environment(\.dismiss) private var dismiss
	@Environment(\.scenePhase) private var scenePhase
	/// nil until geocoded, and when there is no location
	@State private var place: MqttTopicDiscovery.Place?
	@State private var directory = MqttRootDirectory.bundled()
	@State private var geocodeFailed = false
	@State private var custom = ""

	/// `sampler` is for tests and previews that drive one by hand; a default argument cannot create
	/// it because default arguments are evaluated outside the main actor.
	init(config: Binding<ModuleConfig.MQTTConfig>, node: NodeInfoEntity?, autoStart: Bool = true, sampler: MqttTopicSampler? = nil) {
		_config = config
		self.node = node
		self.autoStart = autoStart
		_sampler = StateObject(wrappedValue: sampler ?? MqttTopicSampler())
	}

	private var region: RegionCodes? {
		guard let code = node?.loRaConfig?.regionCode, let region = RegionCodes(rawValue: Int(code)), region != .unset else { return nil }
		return region
	}

	private var settings: MqttTopicSampler.Settings { .init(config: config) }

	/// The connected radio's latest fix first, the phone's location as the fallback; never a prompt.
	private var coordinate: CLLocationCoordinate2D? {
		node?.latestPosition?.nodeCoordinate ?? LocationsHandler.currentLocation
	}

	/// Two decimals (about a kilometer): a live GPS fix drifting a few meters must not re-geocode
	/// once a second while the sample runs.
	private var coordinateKey: String {
		guard let coordinate else { return "none" }
		return String(format: "%.2f,%.2f", coordinate.latitude, coordinate.longitude)
	}

	private var isSampling: Bool {
		switch sampler.phase {
		case .connecting, .subscribing, .sampling: return true
		case .idle, .finished, .failed: return false
		}
	}

	/// Rebuilt from the latest snapshot: the country rung appears once the sample shows the broker
	/// uses it.
	private var plan: MqttTopicDiscovery.Plan {
		guard let region else { return MqttTopicDiscovery.Plan(rungs: []) }
		return MqttTopicDiscovery.plan(
			regionTopic: "msh/" + region.topic,
			regionName: region.description,
			place: place,
			// Community roots placed by radius only need the coordinate, so they still show while
			// the place name is loading or when the geocoder fails (offline, for example).
			at: coordinate,
			directory: directory,
			activity: sampler.activity
		)
	}

	var body: some View {
		SheetNavigationStack {
			List {
				statusSection
				// Without a region there is no ladder and nothing is sampled; only the status row
				// and the custom field make sense.
				if region != nil {
					ladderSection
					activeSection
				}
				customSection
			}
			.navigationTitle("Find Topics")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel") { dismiss() }
				}
			}
		}
		// The sheet inherits the row's `.disabled(!isEditable)`; without this a radio drop while
		// the sheet is open would freeze every row.
		.environment(\.isEnabled, true)
		.task(id: coordinateKey) { await geocode() }
		.task {
			guard autoStart, let fetched = await MqttRootDirectory.fetch() else { return }
			directory = fetched
		}
		.onAppear { startSampling() }
		.onDisappear { sampler.stop() }
		.onChange(of: scenePhase) { _, phase in
			if phase == .background { sampler.stop() }
		}
		.trackScreen(.mqttTopicFinder)
	}

	// MARK: Sections

	private var statusSection: some View {
		Section {
			switch sampler.phase {
			case .idle:
				if autoStart, region == nil {
					Label("Set the LoRa region first", systemImage: "globe")
						.foregroundStyle(.secondary)
				}
			case .connecting:
				HStack {
					ProgressView()
					Text("Connecting…")
				}
			case .subscribing:
				HStack {
					ProgressView()
					Text("Subscribing…")
				}
			case .sampling:
				HStack {
					ProgressView()
					Text("Listening…")
					Spacer()
					Text(remainingText)
						.monospacedDigit()
						.foregroundStyle(.secondary)
				}
				ProgressView(value: min(1, max(0, 1 - Double(sampler.secondsRemaining) / sampler.duration)))
			case .finished:
				Label("Heard \(sampler.messageCount) messages on \(sampler.activity.count) topics", systemImage: "checkmark.circle")
				Button {
					startSampling()
				} label: {
					Label("Sample again", systemImage: "arrow.counterclockwise")
				}
			case .failed(let message):
				Label(message, systemImage: "exclamationmark.triangle")
					.foregroundStyle(.red)
				Button("Try Again") { startSampling() }
			}
		} footer: {
			Text("Listens to \(settings.host) for one minute and publishes nothing. The broker sees your IP address and a random client ID, not your node. Your location is never sent to the broker; Apple's geocoder turns it into the state and city names on the rows. Picking a row fills in the Root Topic field; nothing is sent to the radio until you tap Save.")
		}
	}

	private var ladderSection: some View {
		Section {
			ForEach(plan.rungs) { rung in
				let live = MqttTopicDiscovery.activity(forRung: rung, in: sampler.activity)
				let topic = live?.topic ?? rung.topic
				TopicRow(
					topic: topic,
					title: rung.placeName,
					subtitle: levelName(rung.level),
					count: live?.activity.nodeCount ?? 0,
					truncated: live?.activity.truncated ?? false,
					isCurrent: topic == config.root
				) { pick(topic) }
			}
		} header: {
			Text("Near you")
		} footer: {
			if coordinate == nil {
				Text("No location yet. Connect a radio with a position fix, or allow location access, to see state and city topics.")
			} else if geocodeFailed {
				Text("Could not look up the place name for your location.")
			} else {
				Text("Counts are nodes heard during the sample. Busy topics fill in within seconds; quiet ones may stay at zero.")
			}
		}
	}

	private var activeSection: some View {
		Section {
			let roots = MqttTopicDiscovery.ranked(sampler.activity, plan: plan, from: coordinate).prefix(30)
			if roots.isEmpty {
				if sampler.phase == .finished {
					ContentUnavailableView {
						Label("No local topics heard", systemImage: "antenna.radiowaves.left.and.right.slash")
					} description: {
						if sampler.activity.isEmpty {
							Text("Nothing was heard during the sample.")
						} else {
							Text("Only the topics above were active during the sample.")
						}
					}
				} else if isSampling {
					Text("Nothing heard yet")
						.foregroundStyle(.secondary)
				}
			} else {
				ForEach(roots) { root in
					TopicRow(
						topic: root.root,
						title: nil,
						subtitle: subtitle(for: root),
						count: root.activity.nodeCount,
						truncated: root.activity.truncated,
						isCurrent: root.root == config.root
					) { pick(root.root) }
				}
			}
		} header: {
			Text("Active topics")
		}
	}

	private var customSection: some View {
		Section {
			TextField("Custom topic", text: $custom, prompt: Text(verbatim: "msh/US/WA/seattle"))
				.keyboardType(.asciiCapable)
				.autocorrectionDisabled()
				.textInputAutocapitalization(.never)
				.font(.body.monospaced())
			let sanitized = MqttRootTopic.sanitized(custom)
			let problem = MqttRootTopic.problem(in: sanitized)
			if !custom.isEmpty, let problem {
				Text(problem.message)
					.font(.caption)
					.foregroundStyle(.red)
			}
			Button("Use this topic") { pick(sanitized) }
				.disabled(custom.isEmpty || problem != nil)
		} header: {
			Text("Custom topic")
		} footer: {
			Text("Up to 31 bytes, no leading or trailing slash, no + or #.")
		}
	}

	// MARK: Helpers

	private var remainingText: String {
		let seconds = max(0, sampler.secondsRemaining)
		return String(format: "%d:%02d", seconds / 60, seconds % 60)
	}

	private func levelName(_ level: MqttTopicDiscovery.Rung.Level) -> String {
		switch level {
		case .region:
			return String(localized: "Region")
		case .country:
			return String(localized: "Country", comment: "Topic finder: ladder level name")
		case .state:
			return String(localized: "State or province", comment: "Topic finder: ladder level name")
		case .city:
			return String(localized: "City", comment: "Topic finder: ladder level name")
		case .community:
			return String(localized: "Community mesh", comment: "Topic finder: a named community root from the shared directory that serves the user's area")
		}
	}

	private func subtitle(for root: MqttTopicDiscovery.RankedRoot) -> String? {
		var parts: [String] = []
		let channels = root.activity.channels.sorted()
		if !channels.isEmpty {
			var text = channels.prefix(3).joined(separator: ", ")
			if channels.count > 3 { text += "…" }
			parts.append(text)
		}
		if let distance = root.distance {
			let formatted = Measurement(value: distance, unit: UnitLength.meters)
				.formatted(.measurement(width: .abbreviated, usage: .road))
			parts.append(String(localized: "nearest \(formatted)", comment: "Topic finder: distance to the closest map-reported node"))
		}
		return parts.isEmpty ? nil : parts.joined(separator: " · ")
	}

	private func pick(_ topic: String) {
		config.root = topic
		dismiss()
	}

	private func startSampling() {
		guard autoStart, let region else { return }
		sampler.start(settings: settings, regionTopic: "msh/" + region.topic)
	}

	/// One geocoder call per coordinate; `.task(id:)` cancels and replaces on change and on dismiss.
	/// The previous place stays on screen until the new one arrives. Only a locality makes a city
	/// rung: a county is not a city, and the local roots come from discovery anyway. Names come back
	/// in US English whatever the phone's language, so the directory's subdivision names match and
	/// the roots agree with Android.
	private func geocode() async {
		geocodeFailed = false
		guard let coordinate, autoStart, region != nil else {
			place = nil
			return
		}
		let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
		let placemark = try? await CLGeocoder().reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "en_US")).first
		guard !Task.isCancelled else { return }
		geocodeFailed = placemark == nil
		place = placemark.map {
			MqttTopicDiscovery.Place(countryCode: $0.isoCountryCode, state: $0.administrativeArea, city: $0.locality)
		}
	}
}

/// One topic with its place name or channels and the number of nodes heard on it.
private struct TopicRow: View {
	let topic: String
	let title: String?
	let subtitle: String?
	let count: Int
	let truncated: Bool
	let isCurrent: Bool
	let action: () -> Void

	var body: some View {
		Button(action: action) {
			HStack {
				VStack(alignment: .leading, spacing: 2) {
					Text(topic)
						.font(.callout.monospaced())
					if let title {
						Text(title)
					}
					if let subtitle {
						Text(subtitle)
							.font(.caption)
							.foregroundStyle(.secondary)
					}
				}
				Spacer()
				VStack {
					Text(verbatim: truncated ? "\(count)+" : "\(count)")
						.font(.title3.weight(.semibold))
						.monospacedDigit()
						.foregroundStyle(count > 0 ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
					Text("nodes")
						.font(.caption2)
						.foregroundStyle(.secondary)
				}
				if isCurrent {
					Image(systemName: "checkmark")
						.foregroundStyle(.tint)
				}
			}
		}
		.foregroundStyle(.primary)
		.accessibilityElement(children: .combine)
		.accessibilityAddTraits(isCurrent ? .isSelected : [])
	}
}
