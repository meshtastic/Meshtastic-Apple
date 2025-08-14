//
//  LogRecord+StringRepresentation.swift
//  Meshtastic
//
//  Created by Jake Bordens on 7/29/25.
//

import Foundation
import MeshtasticProtobufs

extension LogRecord {
	var stringRepresentation: String {
		var message = self.source.isEmpty ? self.message : "[\(self.source)] \(self.message)"
		switch self.level {
		case .debug:
			message = "DEBUG | \(message)"
		case .info:
			message = "INFO  | \(message)"
		case .warning:
			message = "WARN  | \(message)"
		case .error:
			message = "ERROR | \(message)"
		case .critical:
			message = "CRIT  | \(message)"
		default:
			message = "DEBUG | \(message)"
		}
		return message
	}
}
