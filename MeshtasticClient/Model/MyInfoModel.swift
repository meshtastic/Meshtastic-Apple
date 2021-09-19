//
//  MyInfoModel.swift
//  MeshtasticClient
//
//  Created by Garth Vander Houwen on 9/16/21.
//

import Foundation

struct MyInfoModel: Identifiable, Codable {
    
    let id = UUID()
    var myNodeNum: UInt32
    var hasGps: Bool
    var numBands: UInt32
    var maxChannels: UInt32
    var firmwareVersion: String
    var rebootCount: UInt32
    var messageTimeoutMsec: UInt32
    var minAppVersion: UInt32
    
}
