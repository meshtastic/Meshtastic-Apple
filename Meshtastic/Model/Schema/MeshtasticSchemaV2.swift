//
//  MeshtasticSchemaV2.swift
//  Meshtastic
//
//  Schema version 2: adds geofence fields to WaypointEntity
//  (geofenceRadius, bounding-box corners, notifyOnEnter / notifyOnExit /
//  notifyFavoritesOnly), backed by the new Waypoint protobuf geofence fields.
//
//  The change is purely additive — no models were added or removed — so the
//  model-type list is unchanged from V1 and the V1→V2 migration is lightweight
//  (see MeshtasticMigrationPlan).
//

import Foundation
import SwiftData

enum MeshtasticSchemaV2: VersionedSchema {
	static var versionIdentifier = Schema.Version(2, 0, 0)

	/// Identical model set to V1 — only WaypointEntity gained additive fields,
	/// so there are no added/removed model types to enumerate here.
	static var models: [any PersistentModel.Type] {
		MeshtasticSchemaV1.models
	}
}
