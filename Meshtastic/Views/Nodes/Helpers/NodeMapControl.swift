//
//  NodeMapControl.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 9/9/23.
//
import SwiftUI
import CoreLocation
import MapKit

struct NodeMapControl: View {
	
	@ObservedObject var node: NodeInfoEntity
	
	var body: some View {
		Text("I am a map")
	}
}
