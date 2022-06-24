//
//  UserEntityExtension.swift
//  MeshtasticApple
//
//  Created by Garth Vander Houwen on 6/3/22.
//

import Foundation

extension UserEntity {
	
	var messageList: [MessageEntity] {
		
		self.value(forKey: "allMessages") as! [MessageEntity]
	}
}
