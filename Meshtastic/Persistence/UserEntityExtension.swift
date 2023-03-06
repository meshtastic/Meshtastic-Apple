//
//  UserEntityExtension.swift
//  MeshtasticApple
//
//  Copyright(c) Garth Vander Houwen 6/3/22.
//

import Foundation

extension UserEntity {

	var messageList: [MessageEntity] {

		self.value(forKey: "allMessages") as? [MessageEntity] ?? [MessageEntity]()
	}

	var adminMessageList: [MessageEntity] {

		self.value(forKey: "adminMessages") as? [MessageEntity] ?? [MessageEntity]()
	}
}
