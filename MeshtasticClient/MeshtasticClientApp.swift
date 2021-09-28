//
//  MeshtasticClientApp.swift
//  MeshtasticClient
//
//  Created by Garth Vander Houwen on 8/18/21.
//

import SwiftUI

@main
struct MeshtasticClientApp: App {

    @ObservedObject private var meshData: MeshData = MeshData()
    @ObservedObject private var messageData: MessageData = MessageData()
    @ObservedObject private var bleManager: BLEManager = BLEManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(meshData)
                .environmentObject(messageData)
                .environmentObject(bleManager)
                .onAppear{
                    meshData.load()
                    messageData.load()
                }
                
        }
    }
}
