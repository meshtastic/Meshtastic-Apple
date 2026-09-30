//
//  ConfigFormMessage.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/18/26.
//
import Foundation
import MeshtasticProtobufs
import SwiftData

/// A configuration message a screen can edit through `MetadataConfigForm`.
///
/// The radio's configuration reaches the app as a proto message and is stored as a
/// SwiftData entity whose property names are the app's own (`outputMilliseconds` for
/// `output_ms`, `usePWM` for `use_pwm`), so the way back from entity to message cannot
/// be generated. Each conforming message writes it by hand, once, in `init(entity:)` -
/// the same dozen lines the old screen had in its `setXValues()`, moved to where the
/// form can call them. Saving sends the whole message; the radio echoes it and the
/// existing `upsertXConfigPacket` writes the entity, as it always has.
protocol ConfigFormMessage: ConfigSchemaMessage {
	associatedtype Entity: PersistentModel
	/// Where the stored copy lives on the node.
	static var entityKeyPath: KeyPath<NodeInfoEntity, Entity?> { get }
	/// The message as the entity holds it.
	init(entity: Entity)
}
