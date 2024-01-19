//
//  CarPlaySceneDelegate.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 1/18/24.
//

import Foundation
import CarPlay

@objc class CarPlaySceneDelegate: NSObject, CPTemplateApplicationSceneDelegate {

	private var interfaceController: CPInterfaceController?
	private var savedTabBarTemplate: CPTabBarTemplate?

	// https://developer.apple.com/documentation/carplay/displaying_content_in_carplay
	// CarPlay calls this function to initialize the scene.
	func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
		// Save the interface controller
		self.interfaceController = interfaceController

		let template = tabBarTemplate()
		self.savedTabBarTemplate = template

		// Create the root template (screen) and install it at the root of the navigation hierarchy.
		interfaceController.setRootTemplate(template, animated: true, completion: nil)
	}

	func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didDisconnectInterfaceController interfaceController: CPInterfaceController) {
		self.interfaceController = nil
	}

	private func tabBarTemplate() -> CPTabBarTemplate {
		return CPTabBarTemplate(templates: [
			channelListTemplate(),
			listTemplate(),
		//	gridTemplate(),
		//	informationTemplate(layout: .leading)
		])
	}

	private func replaceTabs() {
		self.savedTabBarTemplate?.updateTemplates([
			channelListTemplate(),
			listTemplate(),
			gridTemplate(),
			informationTemplate(layout: .leading),
			informationTemplate(layout: .leading),
		])
	}

	private func channelListTemplate() -> CPListTemplate {
		let template = CPListTemplate(
			title: "Channels",
			sections: [
				CPListSection(items: [
					listItem(),
					listItem(),
				], header: nil, sectionIndexTitle: nil),
			]
		)
		template.tabTitle = "Channels"
		template.tabImage = UIImage(systemName: "fibrechannel")// UIImage(named: "RoundIcon")!

		return template
	}

	private func listTemplate() -> CPListTemplate {
		let template = CPListTemplate(
			title: "Direct Messages",
			sections: [
				CPListSection(items: [
					listItem(),
					listItem(),
				], header: nil, sectionIndexTitle: nil),
			]
		)
		template.tabTitle = "Nodes"
		template.tabImage = UIImage(systemName: "message.fill")// UIImage(named: "RoundIcon")!

		return template
	}

	private func listItem() -> CPListTemplateItem {
		let item = CPListItem(text: "Text", detailText: "Detail Text", image: UIImage(named: "RoundIcon")!, accessoryImage: nil, accessoryType: .none)

		item.handler = { [weak self] (item, completion) in
			guard let self = self else {
				completion()
				return
			}

			self.interfaceController?.pushTemplate(
				self.listTemplate(),
				animated: true,
				completion: { (didPresent, error) in
					completion()
				}
			)
		}

		return item
	}

	private func gridTemplate() -> CPGridTemplate {
		let template = CPGridTemplate(
			title: "Grid Title",
			gridButtons: [
				gridButton(),
				gridButton(),
				gridButton(),
				gridButton(),
				gridButton(),
				gridButton(),
			]
		)
		template.tabTitle = "Grid"
		template.tabImage = UIImage(named: "RoundIcon")!

		return template
	}

	private func gridButton() -> CPGridButton {
		return CPGridButton(
			titleVariants: [
				"Maybe a bit much too long of a title",
				"Medium Title",
				"Title"
			],
			image: UIImage(named: "RoundIcon")!,
			handler: { [weak self] button in
				guard let self = self else { return }
				self.interfaceController?.pushTemplate(
					self.gridTemplate(),
					animated: true,
					completion: nil
				)
			}
		)
	}

	private func informationTemplate(layout: CPInformationTemplateLayout) -> CPInformationTemplate {
		let template = CPInformationTemplate(
			title: "Information Title",
			layout: layout,
			items: [
				CPInformationItem(title: "Item\nTitle\nThird\nFourth", detail: "Item\nDetail\nThird line\nFourth line"),
				CPInformationItem(title: "Item Title", detail: nil),
				CPInformationItem(title: "Item Title", detail: "Item Detail"),
				CPInformationItem(title: "Item Title", detail: nil),
				CPInformationItem(title: "Item Title Item Title Item Title Item Title Item Title", detail: "Item Detail Item Detail Item Detail Item Detail Item Detail "),
				CPInformationItem(title: "Item Title", detail: nil),
			],
			actions: [
				textButton(style: .confirm),
				textButton(style: .normal),
//                textButton(style: .cancel),
			]
		)
		template.tabTitle = "Information"
		template.tabImage = UIImage(named: "RoundIcon")!

		return template
	}

	private func textButton(style: CPTextButtonStyle) -> CPTextButton{
		return CPTextButton(
			title: "Text Button",
			textStyle: style,
			handler: { [weak self] button in
				guard let self = self else { return }
				self.interfaceController?.pushTemplate(
					self.informationTemplate(layout: .twoColumn),
					animated: true,
					completion: nil
				)

//                self.replaceTabs()
			}
		)
	}
}
