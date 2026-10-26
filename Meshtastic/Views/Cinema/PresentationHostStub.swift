//
//  PresentationHostStub.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/25/26.
//
//  TEMPORARY: delete this file when merging with the presentation helpers
//  (Meshtastic/Extensions/PresentationHost.swift), which define the same key.

import SwiftUI

/// Where a view is shown: in a window, or on a panel in an immersive space, where sheets never
/// appear.
enum PresentationHost {
	case window
	case panel
}

extension EnvironmentValues {
	@Entry var presentationHost: PresentationHost = .window
}
