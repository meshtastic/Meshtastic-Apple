//
//  MeshMapContainer.swift
//  Meshtastic
//
//  Selects between the production SwiftUI `MeshMap` and the new MKMapView-backed `MeshMapMK`
//  (offline/topo raster basemap + native clustering + custom SwiftUI annotations). Per the migration
//  plan we "replace now": the flag DEFAULTS to the new map, and the toggle in Map Settings flips back
//  to the old SwiftUI map as an escape hatch while the new one reaches full parity. The flag is read
//  here at the call site so neither map implementation is mutated by the other and the OFF path is
//  byte-identical to today.
//

import SwiftUI

struct MeshMapContainer: View {
	@ObservedObject var router: Router
	var showOpenWindowButton: Bool = true

	@AppStorage("useMeshMapMK") private var useMeshMapMK = true

	var body: some View {
		if useMeshMapMK {
			MeshMapMK(router: router, showOpenWindowButton: showOpenWindowButton)
		} else {
			MeshMap(router: router, showOpenWindowButton: showOpenWindowButton)
		}
	}
}
