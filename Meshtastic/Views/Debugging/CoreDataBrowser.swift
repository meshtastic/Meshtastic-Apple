//
//  CoreDataBrowser.swift
//  Meshtastic
//
//  Created by Jake Bordens on 12/9/25.
//

import SwiftUI
import CoreData
import SwiftDraw
// MARK: - 1. Root Browser (The Menu)

struct CoreDataBrowser: View {
	@Environment(\.managedObjectContext) private var viewContext
	
	var entityNames: [String] {
		// extract all entities from the model attached to the context
		return viewContext.persistentStoreCoordinator?
			.managedObjectModel.entitiesByName.keys.sorted() ?? []
	}
	
	var body: some View {
		List {
			Section(header: Text("Entities")) {
				if entityNames.isEmpty {
					Text("No Entities Found")
						.foregroundColor(.secondary)
				} else {
					ForEach(entityNames, id: \.self) { name in
						NavigationLink(destination: DynamicEntityListView(entityName: name)) {
							Label(name, systemImage: "tablecells")
						}
					}
				}
			}
		}
		.navigationTitle("Database Browser")
	}
}

// MARK: - 2. Dynamic List View (Fetch Request by Name)

/// Lists entities based on a String Entity Name, not a compile-time Type.
struct DynamicEntityListView: View {
	let entityName: String
	@FetchRequest var fetchRequest: FetchedResults<NSManagedObject>
	
	init(entityName: String) {
		self.entityName = entityName
		
		// Construct a fetch request for the base NSManagedObject
		let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
		
		// We need a default sort descriptor for FetchRequest to work happily.
		// Sorting by objectID keeps them in insertion/creation order usually.
		request.sortDescriptors = [NSSortDescriptor(key: "objectID", ascending: true)]
		
		self._fetchRequest = FetchRequest(fetchRequest: request)
	}
	
	var body: some View {
		List(fetchRequest, id: \.objectID) { object in
			EntityRow(object: object)
		}
		.navigationTitle(entityName)
		.overlay {
			if fetchRequest.isEmpty {
				ContentUnavailableView("Table Empty", systemImage: "tray", description: Text("No records found for \(entityName)"))
			}
		}
	}
}

// MARK: - 3. Relationship List (In-Memory List)

/// Used when navigating to a To-Many relationship (data is already in memory/faulted)
struct RelationshipListView: View {
	let title: String
	let objects: [NSManagedObject]
	
	var body: some View {
		List(objects, id: \.objectID) { object in
			EntityRow(object: object)
		}
		.navigationTitle(title)
	}
}

// MARK: - 4. Shared Row View

struct EntityRow: View {
	@ObservedObject var object: NSManagedObject
	
	var body: some View {
		NavigationLink(destination: EntityDetailView(object: object)) {
			VStack(alignment: .leading) {
				Text(object.debugDisplayName)
					.font(.headline)
					.lineLimit(1)
				Text(object.objectID.uriRepresentation().lastPathComponent)
					.font(.caption)
					.foregroundColor(.secondary)
			}
		}
	}
}

// MARK: - 5. Detail View (The Introspector)

struct EntityDetailView: View {
	@ObservedObject var object: NSManagedObject
	
	var attributes: [String: NSAttributeDescription] {
		return object.entity.attributesByName
	}
	
	var relationships: [String: NSRelationshipDescription] {
		return object.entity.relationshipsByName
	}
	
	var body: some View {
		Form {
			Section(header: Text("Metadata")) {
				LabeledContent("Object ID", value: object.objectID.uriRepresentation().lastPathComponent)
				LabeledContent("Entity Name", value: object.entity.name ?? "Unknown")
			}
			
			Section(header: Text("Attributes")) {
				ForEach(attributes.keys.sorted(), id: \.self) { key in
					if let value = object.value(forKey: key) {
						AttributeRow(key: key, value: value, type: attributes[key]?.attributeType)
					} else {
						LabeledContent(key, value: "nil")
							.foregroundColor(.secondary)
					}
				}
			}
			
			if !relationships.isEmpty {
				Section(header: Text("Relationships")) {
					ForEach(relationships.keys.sorted(), id: \.self) { key in
						RelationshipNavigationRow(key: key, object: object)
					}
				}
			}
		}
		.navigationTitle("Details")
		.navigationBarTitleDisplayMode(.inline)
	}
}

// MARK: - 6. Relationship Navigation Logic

struct RelationshipNavigationRow: View {
	let key: String
	@ObservedObject var object: NSManagedObject
	
	var body: some View {
		let value = object.value(forKey: key)
		
		if let set = value as? Set<NSManagedObject> {
			// To-Many (Unordered)
			NavigationLink {
				RelationshipListView(
					title: key,
					objects: set.sorted { $0.debugDisplayName < $1.debugDisplayName }
				)
			} label: {
				HStack {
					Text(key)
					Spacer()
					Text("\(set.count)")
						.foregroundColor(.secondary)
					Image(systemName: "folder")
						.foregroundColor(.blue)
				}
			}
			.disabled(set.isEmpty)
		} else if let orderedSet = value as? NSOrderedSet {
			// To-Many (Ordered)
			let array = orderedSet.array as? [NSManagedObject] ?? []
			NavigationLink {
				RelationshipListView(title: key, objects: array)
			} label: {
				HStack {
					Text(key)
					Spacer()
					Text("\(array.count)")
						.foregroundColor(.secondary)
					Image(systemName: "folder")
						.foregroundColor(.blue)
				}
			}
			.disabled(array.isEmpty)
		} else if let singleObject = value as? NSManagedObject {
			// To-One
			NavigationLink {
				EntityDetailView(object: singleObject)
			} label: {
				HStack {
					Text(key)
					Spacer()
					Text(singleObject.debugDisplayName)
						.lineLimit(1)
						.truncationMode(.tail)
						.foregroundColor(.secondary)
						.font(.caption)
				}
			}
		} else {
			// Nil
			HStack {
				Text(key)
				Spacer()
				Text("nil")
					.foregroundColor(.secondary)
			}
		}
	}
}

// MARK: - 7. Attribute Formatter

struct AttributeRow: View {
	let key: String
	let value: Any
	let type: NSAttributeType?
	
	var body: some View {
		VStack(alignment: .leading) {
			Text(key).font(.caption).foregroundColor(.secondary)
			content
		}
		.padding(.vertical, 2)
	}
	
	@ViewBuilder
	var content: some View {
		if let type = type {
			switch type {
			case .booleanAttributeType:
				if let boolVal = value as? Bool {
					Label(boolVal ? "True" : "False", systemImage: boolVal ? "checkmark.circle.fill" : "xmark.circle")
						.foregroundColor(boolVal ? .green : .red)
				}
			case .dateAttributeType:
				if let date = value as? Date {
					Text(date.formatted(date: .abbreviated, time: .standard))
				}
			case .binaryDataAttributeType:
				if key == "svgData", let data = value as? Data, let svg = SVG(data: data) {
					// Magic field name telliing us this is an SVG
					SVGView(svg: svg)
						.resizable()
						.aspectRatio(contentMode: .fit)
						.frame(maxWidth: 200, maxHeight: 200)
				} else if let data = value as? Data {
					Text("Binary Data (\(data.count) bytes)")
						.font(.system(.body, design: .monospaced))
				}
			case .transformableAttributeType:
				Text(String(describing: value))
					.font(.caption)
					.lineLimit(3)
			default:
				Text(String(describing: value))
			}
		} else {
			Text(String(describing: value))
		}
	}
}

// MARK: - 8. Smart Name Helper

extension NSManagedObject {
	var debugDisplayName: String {
		let keys = self.entity.attributesByName.keys
		// Heuristic to find a displayable title
		let preferredKeys = ["name", "title", "fullName", "username", "email", "identifier", "uuid", "id"]
		
		for key in preferredKeys {
			if keys.contains(key), let val = self.value(forKey: key) as? String, !val.isEmpty {
				return val
			}
		}
		
		// Fallback: use first string property found
		for key in keys {
			if let val = self.value(forKey: key) as? String, !val.isEmpty {
				return val
			}
		}
		
		return "Unnamed Entity"
	}
}
