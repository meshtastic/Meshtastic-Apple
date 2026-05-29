//
//  IntentHandler.swift
//  Meshtastic
//
//  Routes incoming SiriKit intents to the appropriate handler.
//  Used by the app delegate for in-app intent handling to support
//  CarPlay messaging and Siri voice commands.
//

#if os(iOS)
import Intents

final class IntentHandler: INExtension {

	override func handler(for intent: INIntent) -> Any? {
		switch intent {
		case is INSendMessageIntent:
			return SendMessageIntentHandler()
		case is INSearchForMessagesIntent:
			return SearchForMessagesIntentHandler()
		case is INSetMessageAttributeIntent:
			return SetMessageAttributeIntentHandler()
		default:
			return nil
		}
	}
}
#endif
