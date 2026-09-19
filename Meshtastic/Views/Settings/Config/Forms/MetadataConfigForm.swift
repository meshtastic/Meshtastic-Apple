//
//  MetadataConfigForm.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/18/26.
//
import OSLog
import SwiftUI
import MeshtasticProtobufs

/// A configuration screen driven by the schema.
///
/// Holds the whole message as state, lays it out from the screen's overlay, and reads
/// every label, description and unit from the registry. It keeps the contract the
/// hand-written screens share - `ConfigHeader` loads the values, the form is disabled
/// without a radio or a stored config, `SaveConfigButton` appears only with changes,
/// `performConfigSave` sends and dismisses, `requestRemoteConfig` asks a remote node -
/// with two differences worth knowing. Changes are tracked by comparing the message to
/// what was loaded, so reverting an edit makes the Save button disappear again; and a
/// failed save shows an alert instead of only logging.
struct MetadataConfigForm<M: ConfigFormMessage, Leading: View, Trailing: View>: View {
	@Environment(\.modelContext) private var context
	@EnvironmentObject private var accessoryManager: AccessoryManager
	@Environment(\.dismiss) private var goBack

	let node: NodeInfoEntity?
	/// The `ConfigHeader` title, e.g. "Serial".
	let title: String
	let overlay: ConfigFormOverlay<M>
	/// Load-time migrations the old screen's `setXValues()` did: an interval floor, a
	/// retired enum value mapped forward. Applied to the in-memory copy, never the entity.
	var normalize: (M) -> M = { $0 }
	/// Runs after every edit, for one field's change to adjust another.
	var reconcile: ((inout M, ConfigFormEnvironment) -> Void)?
	/// Gate on the Save button beyond "something changed".
	var canSave: (M) -> Bool = { _ in true }
	/// Replaces the default "the node will reboot" confirmation.
	var confirmationMessage: String?
	/// A change the message does not hold - text sent in a separate admin message, say -
	/// so the Save button appears for it too.
	var externalChanges = false
	let request: (UserEntity, UserEntity) async throws -> Void
	let save: (M, UserEntity, UserEntity) async throws -> Void
	/// Bespoke content above the sections: warnings, a placement summary, a control
	/// that edits several fields at once.
	@ViewBuilder let leading: (Binding<M>) -> Leading
	/// Bespoke content below them: reset buttons, app-local toggles, anything the
	/// schema does not hold.
	@ViewBuilder let trailing: (Binding<M>) -> Trailing

	@State private var config = M()
	@State private var original = M()
	@State private var loaded = false
	@State private var saveError: String?
	/// The message as it was when Save was tapped. The form is locked while this is
	/// set, and on success it - not whatever `config` holds by then - becomes the
	/// new baseline, so nothing typed mid-flight is ever marked as saved.
	@State private var inFlight: M?
	/// The row a search result asked for, marked briefly so the eye lands on it.
	@State private var highlightedRow: String?
	@Environment(\.settingsFieldFocus) private var settingsFieldFocus

	init(
		node: NodeInfoEntity?,
		title: String,
		overlay: ConfigFormOverlay<M>,
		normalize: @escaping (M) -> M = { $0 },
		reconcile: ((inout M, ConfigFormEnvironment) -> Void)? = nil,
		canSave: @escaping (M) -> Bool = { _ in true },
		confirmationMessage: String? = nil,
		externalChanges: Bool = false,
		request: @escaping (UserEntity, UserEntity) async throws -> Void,
		save: @escaping (M, UserEntity, UserEntity) async throws -> Void,
		@ViewBuilder leading: @escaping (Binding<M>) -> Leading,
		@ViewBuilder trailing: @escaping (Binding<M>) -> Trailing
	) {
		self.node = node
		self.title = title
		self.overlay = overlay
		self.normalize = normalize
		self.reconcile = reconcile
		self.canSave = canSave
		self.confirmationMessage = confirmationMessage
		self.externalChanges = externalChanges
		self.request = request
		self.save = save
		self.leading = leading
		self.trailing = trailing
	}

	/// `SaveConfigButton` and `performConfigSave` want a binding. Setting it false is
	/// how a successful save resets the baseline.
	private var hasChanges: Binding<Bool> {
		Binding(
			get: { loaded && (config != original || externalChanges) },
			set: { changed in
				guard !changed else { return }
				original = inFlight ?? config
				inFlight = nil
			}
		)
	}

	/// Whether the controls accept input. Without a radio, or before its config has
	/// arrived, the screen still renders what it knows and can be read and scrolled -
	/// only the controls are inert. Disabling the `Form` itself would take the scroll
	/// gesture with it and leave the screen unreadable below the fold.
	private var isEditable: Bool {
		accessoryManager.isConnected && node?[keyPath: M.entityKeyPath] != nil && inFlight == nil
	}

	private var environment: ConfigFormEnvironment {
		ConfigFormEnvironment(
			node: node,
			isConnected: accessoryManager.isConnected,
			isConnectedNode: node != nil && node?.num == accessoryManager.activeDeviceNum,
			isDIYHardware: DIYHardware.isDIY(slug: node?.user?.hwModel),
			hasWifi: node?.metadata?.hasWifi ?? false,
			hasEthernet: node?.metadata?.hasEthernet ?? false,
			hasXeddsa: node?.metadata?.hasXeddsa ?? false,
			firmwareAtLeast: { accessoryManager.checkIsVersionSupported(forVersion: $0) }
		)
	}

	var body: some View {
		let env = environment
		ScrollViewReader { proxy in
		Form {
			ConfigHeader(title: title, config: M.entityKeyPath, node: node, onAppear: load)
			leading($config)
				.disabled(!isEditable)
			ForEach(overlay.sections) { section in
				if section.shownWhen?.evaluate(config, env) ?? true {
					let visible = section.fields.filter { isVisible($0, env) }
					if !visible.isEmpty {
						Section {
							ForEach(visible) { field in
								ConfigFormFieldRow(field: field, config: $config, environment: env)
									.id(field.id)
									.listRowBackground(highlightedRow == field.id ? Color.accentColor.opacity(0.15) : nil)
									.disabled(!isEditable || !(field.enabledWhen?.evaluate(config, env) ?? true))
							}
						} header: {
							if let title = section.title { Text(title) }
						} footer: {
							if let footer = section.footer { Text(footer) }
						}
						.disabled(!(section.enabledWhen?.evaluate(config, env) ?? true))
					}
				}
			}
			trailing($config)
				.disabled(!isEditable)
		}
		.scrollDismissesKeyboard(.immediately)
		.safeAreaInset(edge: .bottom, alignment: .center) {
			HStack(spacing: 0) {
				if let confirmationMessage {
					SaveConfigButton(node: node, hasChanges: hasChanges, confirmationMessage: confirmationMessage) { performSave() }
						.disabled(!canSave(config) || inFlight != nil)
				} else {
					SaveConfigButton(node: node, hasChanges: hasChanges) { performSave() }
						.disabled(!canSave(config) || inFlight != nil)
				}
			}
		}
		.alert(String(localized: "Save failed", comment: "Config save error title"),
			   isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
			Button(String(localized: "OK", comment: "Dismiss")) { saveError = nil }
		} message: {
			Text(saveError ?? "")
		}
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				ConnectedDevice(deviceConnected: accessoryManager.isConnected,
								name: accessoryManager.activeConnection?.device.shortName ?? "?")
			}
		}
		.onFirstAppear {
			requestRemoteConfig(node: node, context: context, accessoryManager: accessoryManager,
								configIsNil: { $0[keyPath: M.entityKeyPath] == nil }, request: request)
		}
		.onChange(of: config) { _, _ in
			guard let reconcile else { return }
			var adjusted = config
			reconcile(&adjusted, env)
			if adjusted != config { config = adjusted }
		}
		// A view-bound task, so leaving the screen mid-scroll cancels it rather than
		// letting it move a form the reader has already navigated away from.
		.task { await focusSearchedControl(using: proxy, env) }
		}
	}

	/// A search result names one control, so scroll to it and mark it rather than leaving
	/// the reader to pick it out of rows that all look alike.
	@MainActor
	private func focusSearchedControl(using proxy: ScrollViewProxy, _ env: ConfigFormEnvironment) async {
		guard let target = settingsFieldFocus.target else { return }
		// Taken whether or not this screen can honour it: a request left pending would be
		// picked up later by whichever screen does own the field.
		settingsFieldFocus.clear()
		// Only rows that are actually on screen can be scrolled to. A field behind a
		// toggle that is off - NeighborInfo's interval, say - has no row today, so the
		// screen just opens.
		guard let row = overlay.rowID(for: target),
			  overlay.sections.flatMap(\.fields).contains(where: { $0.id == row && isVisible($0, env) })
		else { return }
		do {
			// The rows exist only after the form's first layout pass.
			try await Task.sleep(for: .milliseconds(350))
			withAnimation { proxy.scrollTo(row, anchor: .center) }
			highlightedRow = row
			try await Task.sleep(for: .seconds(2))
			withAnimation { highlightedRow = nil }
		} catch {
			// Cancelled by leaving the screen; the mark goes with it.
			highlightedRow = nil
		}
	}

	/// The overlay's condition, then the schema's own hiding rules: a DIY-only field
	/// on hardware not tagged DIY, and a deprecated field still at its zero value.
	private func isVisible(_ field: ConfigFormField<M>, _ env: ConfigFormEnvironment) -> Bool {
		if let condition = field.shownWhen, !condition.evaluate(config, env) { return false }
		let metadata = field.field.metadata
		if metadata?.diyOnly == true, env.isConnected, !env.isDIYHardware { return false }
		return true
	}

	private func load() {
		guard let entity = node?[keyPath: M.entityKeyPath] else { return }
		let message = normalize(M(entity: entity))
		config = message
		original = message
		loaded = true
	}

	private func performSave() {
		let sent = config
		inFlight = sent
		performConfigSave(node: node, context: context, accessoryManager: accessoryManager,
						  hasChanges: hasChanges, dismiss: goBack,
						  onError: { message in
							  saveError = message
							  inFlight = nil
						  }) { fromUser, toUser in
			try await save(sent, fromUser, toUser)
		}
	}
}
// Swift will not default a generic view-builder parameter, so the common shapes -
// no bespoke content, or only one side of it - get their own initialisers.
extension MetadataConfigForm where Leading == EmptyView, Trailing == EmptyView {
	init(
		node: NodeInfoEntity?, title: String, overlay: ConfigFormOverlay<M>,
		normalize: @escaping (M) -> M = { $0 },
		reconcile: ((inout M, ConfigFormEnvironment) -> Void)? = nil,
		canSave: @escaping (M) -> Bool = { _ in true },
		confirmationMessage: String? = nil,
		externalChanges: Bool = false,
		request: @escaping (UserEntity, UserEntity) async throws -> Void,
		save: @escaping (M, UserEntity, UserEntity) async throws -> Void
	) {
		self.init(
			node: node, title: title, overlay: overlay, normalize: normalize, reconcile: reconcile,
			canSave: canSave, confirmationMessage: confirmationMessage, externalChanges: externalChanges,
			request: request, save: save,
			leading: { _ in EmptyView() }, trailing: { _ in EmptyView() }
		)
	}
}

extension MetadataConfigForm where Trailing == EmptyView {
	init(
		node: NodeInfoEntity?, title: String, overlay: ConfigFormOverlay<M>,
		normalize: @escaping (M) -> M = { $0 },
		reconcile: ((inout M, ConfigFormEnvironment) -> Void)? = nil,
		canSave: @escaping (M) -> Bool = { _ in true },
		confirmationMessage: String? = nil,
		externalChanges: Bool = false,
		request: @escaping (UserEntity, UserEntity) async throws -> Void,
		save: @escaping (M, UserEntity, UserEntity) async throws -> Void,
		@ViewBuilder leading: @escaping (Binding<M>) -> Leading
	) {
		self.init(
			node: node, title: title, overlay: overlay, normalize: normalize, reconcile: reconcile,
			canSave: canSave, confirmationMessage: confirmationMessage, externalChanges: externalChanges,
			request: request, save: save,
			leading: leading, trailing: { _ in EmptyView() }
		)
	}
}

extension MetadataConfigForm where Leading == EmptyView {
	init(
		node: NodeInfoEntity?, title: String, overlay: ConfigFormOverlay<M>,
		normalize: @escaping (M) -> M = { $0 },
		reconcile: ((inout M, ConfigFormEnvironment) -> Void)? = nil,
		canSave: @escaping (M) -> Bool = { _ in true },
		confirmationMessage: String? = nil,
		externalChanges: Bool = false,
		request: @escaping (UserEntity, UserEntity) async throws -> Void,
		save: @escaping (M, UserEntity, UserEntity) async throws -> Void,
		@ViewBuilder trailing: @escaping (Binding<M>) -> Trailing
	) {
		self.init(
			node: node, title: title, overlay: overlay, normalize: normalize, reconcile: reconcile,
			canSave: canSave, confirmationMessage: confirmationMessage, externalChanges: externalChanges,
			request: request, save: save,
			leading: { _ in EmptyView() }, trailing: trailing
		)
	}
}
