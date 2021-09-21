//
//  MeshtasticClientApp.swift
//  MeshtasticClient
//
//  Created by Garth Vander Houwen on 8/18/21.
//

import SwiftUI

@main
struct MeshtasticClientApp: App {

    @ObservedObject private var meshData = MeshData()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(meshData)
                .onAppear{
                    meshData.load()
                }
                
        }
    }
}
