//
//  CoreDataBrowser.swift
//  Meshtastic
//
//  Created by Jake Bordens on 12/9/25.
//

import SwiftUI
import SwiftData
import SwiftDraw

// MARK: - Fetch Helper

/// Opens the existential `any PersistentModel.Type` to call a generic fetch.
private func fetchAll(of modelType: any PersistentModel.Type, context: ModelContext, limit: Int = 100) -> [any PersistentModel] {
	func _fetch<T: PersistentModel>(_ type: T.Type) -> [any PersistentModel] {
		var descriptor = FetchDescriptor<T>()
		descriptor.fetchLimit = limit
		return (try? context.fetch(descriptor)) ?? []
	}
	return _fetch(modelType)
}

/// Returns the total count for a model type.
private func fetchCount(of modelType: any PersistentModel.Type, context: ModelContext) -> Int {
	func _count<T: PersistentModel>(_ type: T.Type) -> Int {
		(try? context.fetchCount(FetchDescriptor<T>())) ?? 0
	}
	return _count(modelType)
}

// MARK: - 1. Root Browser (The Menu)

struct CoreDataBrowser: View {
	@Environment(\.modelContext) private var modelContext

	private var sortedModels: [(name: String, type: any PersistentModel.Type)] {
		MeshtasticSchema.allModels.map { type in
			(name: String(describing: type), type: type)
		}.sorted { $0.name < $1.name }
	}

	var body: some View {
		List {
			Section(header: Text("Entities (\(sortedModels.count))")) {
				ForEach(sortedModels, id: \.name) { model in
					NavigationLink(destination: DynamicEntityListView(modelType: model.type, entityName: model.name)) {
						HStack {
							Label(model.name, systemImage: "tablecells")
							Spacer()
							Text("\(fetchCount(of: model.type, context: modelContext))")
								.foregroundColor(.secondary)
								.font(.caption)
						}
					}
				}
			}
		}
		.navigationTitle("Database Browser")
	}
}

// MARK: - 2. Dynamic List View

struct DynamicEntityListView: View {
	let modelType: any PersistentModel.Type
	let entityName: String
	@Environment(\.modelContext) private var modelContext
	@State private var objects: [any PersistentModel] = []

	var body: some View {
		List(objects.indices, id: \.self) { index in
			let object = objects[index]
			NavigationLink(destination: EntityDetailView(object: object)) {
				VStack(alignment: .leading) {
					Text(displayName(for: object))
						.font(.headline)
						.lineLimit(1)
					Text(object.persistentModelID.hashValue.description)
						.font(.caption)
						.foregroundColor(.secondary)
				}
			}
		}
		.navigationTitle("\(entityName) (\(objects.count))")
		.overlay {
			if objects.isEmpty {
				ContentUnavailableView("Table Empty", systemImage: "tray", description: Text("No records found for \(entityName)"))
			}
		}
		.onAppear {
			objects = fetchAll(of: modelType, context: modelContext, limit: 500)
		}
	}
}

// MARK: - 3. Detail View

struct EntityDetailView: View {
	let object: any PersistentModel

	var body: some View {
		let mirror = Mirror(reflecting: object)
		let properties = mirror.children.compactMap { child -> (label: String, value: Any)? in
			guard let label = child.label else { return nil }
			// Strip underscore prefix from stored property backing
			let cleanLabel = label.hasPrefix("_") ? String(label.dropFirst()) : label
			return (label: cleanLabel, value: child.value)
		}.sorted { $0.label < $1.label }

		Form {
			Section(header: Text("Metadata")) {
				LabeledContent("Type", value: String(describing: type(of: object)))
				LabeledContent("ID", value: object.persistentModelID.hashValue.description)
			}

			Section(header: Text("Properties (\(properties.count))")) {
				ForEach(properties, id: \.label) { prop in
					PropertyRow(key: prop.label, value: prop.value)
				}
			}
		}
		.navigationTitle("Details")
		.navigationBarTitleDisplayMode(.inline)
	}
}

// MARK: - 4. Property Row

struct PropertyRow: View {
	let key: String
	let value: Any

	var body: some View {
		VStack(alignment: .leading) {
			Text(key)
				.font(.caption)
				.foregroundColor(.secondary)
			content
		}
		.padding(.vertical, 2)
	}

	@ViewBuilder
	var content: some View {
		let unwrapped = unwrapOptional(value)

		if unwrapped == nil {
			Text("nil")
				.foregroundColor(.secondary)
				.italic()
		} else if let boolVal = unwrapped as? Bool {
			Label(boolVal ? "True" : "False", systemImage: boolVal ? "checkmark.circle.fill" : "xmark.circle")
				.foregroundColor(boolVal ? .green : .red)
		} else if let date = unwrapped as? Date {
			Text(date.formatted(date: .abbreviated, time: .standard))
		} else if let data = unwrapped as? Data {
			if key == "svgData", let svg = SVG(data: data) {
				SVGView(svg: svg)
					.resizable()
					.aspectRatio(contentMode: .fit)
					.frame(maxWidth: 200, maxHeight: 200)
			} else {
				Text("Binary Data (\(data.count) bytes)")
					.font(.system(.body, design: .monospaced))
			}
		} else if let intVal = unwrapped as? any FixedWidthInteger {
			Text(String(describing: intVal))
				.font(.system(.body, design: .monospaced))
		} else if let floatVal = unwrapped as? Float {
			Text(String(format: "%.4f", floatVal))
				.font(.system(.body, design: .monospaced))
		} else if let doubleVal = unwrapped as? Double {
			Text(String(format: "%.6f", doubleVal))
				.font(.system(.body, design: .monospaced))
		} else if let array = unwrapped as? [any PersistentModel] {
			NavigationLink {
				RelationshipListView(title: key, objects: array)
			} label: {
				HStack {
					Text("[\(array.count) items]")
						.foregroundColor(.secondary)
					Image(systemName: "folder")
						.foregroundColor(.blue)
				}
			}
			.disabled(array.isEmpty)
		} else if let related = unwrapped as? any PersistentModel {
			NavigationLink {
				EntityDetailView(object: related)
			} label: {
				Text(displayName(for: related))
					.foregroundColor(.secondary)
					.lineLimit(1)
			}
		} else {
			Text(String(describing: unwrapped!))
				.lineLimit(3)
		}
	}
}

// MARK: - 5. Relationship List

struct RelationshipListView: View {
	let title: String
	let objects: [any PersistentModel]

	var body: some View {
		List(objects.indices, id: \.self) { index in
			let object = objects[index]
			NavigationLink(destination: EntityDetailView(object: object)) {
				VStack(alignment: .leading) {
					Text(displayName(for: object))
						.font(.headline)
						.lineLimit(1)
					Text(String(describing: type(of: object)))
						.font(.caption)
						.foregroundColor(.secondary)
				}
			}
		}
		.navigationTitle("\(title) (\(objects.count))")
	}
}

// MARK: - 6. Helpers

/// Unwrap an optional `Any` value.
private func unwrapOptional(_ value: Any) -> Any? {
	let mirror = Mirror(reflecting: value)
	if mirror.displayStyle == .optional {
		return mirror.children.first?.value
	}
	return value
}

/// Find a displayable name from a model instance using heuristic key search.
private func displayName(for object: any PersistentModel) -> String {
	let mirror = Mirror(reflecting: object)
	let preferredKeys = ["longName", "name", "title", "shortName", "userId", "messagePayload"]

	for key in preferredKeys {
		if let child = mirror.children.first(where: { $0.label == "_\(key)" || $0.label == key }),
		   let unwrapped = unwrapOptional(child.value) as? String,
		   !unwrapped.isEmpty {
			return unwrapped
		}
	}

	// Fallback: first non-empty string property
	for child in mirror.children {
		if let unwrapped = unwrapOptional(child.value) as? String, !unwrapped.isEmpty {
			return unwrapped
		}
	}

	return String(describing: type(of: object))
}
