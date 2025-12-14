//
//  DeviceHardwareImage.swift
//  Meshtastic
//
//  Created by jake on 12/6/25.
//

import SwiftUI
import CoreData
import SwiftDraw

struct DeviceHardwareImage<T>: View where T: BinaryInteger, T: CVarArg {
	@Environment(\.managedObjectContext) var context
	@FetchRequest var hardware: FetchedResults<DeviceHardwareEntity>
	@EnvironmentObject var meshtasticAPI: MeshtasticAPI
	
	// This closure lets the caller define modifiers on the Image
	@State private var gridSize: CGSize = .zero
	
	init(hwId: T) {
		
		let predicate = NSPredicate(format: "hwModel == %d", hwId)
		_hardware = FetchRequest(
			entity: DeviceHardwareEntity.entity(),
			sortDescriptors: [NSSortDescriptor(key: "hwModelSlug", ascending: true)],
			predicate: predicate,
			animation: .default
		)
	}
	
	var potentialImages: [DeviceHardwareImageEntity] {
		var returnImages = [DeviceHardwareImageEntity]()
		var seenFileNames = Set<String>()
		for item in hardware {
			if let imageList = item.images  as? Set<DeviceHardwareImageEntity> {
				for image in imageList {
					if image.svgData != nil {
						let name = image.fileName ?? ""
						if !seenFileNames.contains(name) {
							seenFileNames.insert(name)
							returnImages.append(image)
						}
					}
					if returnImages.count >= 4 {
						break
					}
				}
			}
		}
		
		// Sort to keep the order somewhat deterministic
		return returnImages.sorted(by: {$0.fileName ?? "" < $1.fileName ?? ""})
	}
	
	var body: some View {
		// 1. Define the footprint.
		// We use Color.clear so it takes up space but is invisible.
		Color.clear
			.aspectRatio(1, contentMode: .fit) // Enforce square aspect ratio (or change as needed)
		// 2. Measure the size of this footprint using the new modifier
			.onGeometryChange(for: CGSize.self) { proxy in
				proxy.size
			} action: { newValue in
				gridSize = newValue
			}
		// 3. Draw the actual content on top using the measured size
			.overlay {
				let images = self.potentialImages
				if images.count > 0, gridSize != .zero {
					content(size: gridSize, images: self.potentialImages)
				} else if meshtasticAPI.isLoadingDeviceList {
					ProgressView()
				} else {
					EmptyView()
				}
			}
	}
	
	@ViewBuilder
	private func content(size: CGSize, images: [DeviceHardwareImageEntity]) -> some View {
		let spacing: CGFloat = 10.0
		switch images.count {
		case 0:
			Image("UNSET")
				.resizable()
				.aspectRatio(contentMode: .fit)
				.frame(width: size.width, height: size.height)
			
		case 1:
			if let svgData = images[0].svgData, let svg = SVG(data: svgData) {
				SVGView(svg: svg)
					.resizable()
					.aspectRatio(contentMode: .fit)
					.frame(width: size.width, height: size.height)
			}
		case 2:
			HStack(spacing: spacing) {
				ForEach(0..<2, id: \.self) { i in
					if let svgData = images[0].svgData, let svg = SVG(data: svgData) {
						SVGView(svg: svg)
							.resizable()
							.aspectRatio(contentMode: .fit)
							.frame(width: (size.width - 2) / 2,
								   height: size.height)
					}
				}
			}
			
		case 3:
			HStack(spacing: spacing) {
				// Big image on the Left
				if let svgData = images[0].svgData, let svg = SVG(data: svgData) {
					SVGView(svg: svg)
						.resizable()
						.aspectRatio(contentMode: .fit)
						.frame(width: (size.width * 0.6) - 1,
							   height: size.height)
				}
				
				// Two stacked on the Right
				VStack(spacing: spacing) {
					if let svgData = images[0].svgData, let svg = SVG(data: svgData) {
						SVGView(svg: svg)
							.resizable()
							.aspectRatio(contentMode: .fit)
							.frame(maxWidth: .infinity, maxHeight: .infinity) // Flex fill
					}
					if let svgData = images[0].svgData, let svg = SVG(data: svgData) {
						SVGView(svg: svg)
							.resizable()
							.aspectRatio(contentMode: .fit)
							.frame(maxWidth: .infinity, maxHeight: .infinity) // Flex fill
					}
				}
				.frame(width: (size.width * 0.4) - 1,
					   height: size.height)
			}
			
		default: // 4 items
			let halfWidth = (size.width - 2) / 2
			let halfHeight = (size.height - 2) / 2
			
			VStack(spacing: spacing) {
				HStack(spacing: spacing) {
					if let svgData = images[0].svgData, let svg = SVG(data: svgData) {
						SVGView(svg: svg)
							.resizable()
							.aspectRatio(contentMode: .fit)
							.frame(width: halfWidth, height: halfHeight)
					}
					if let svgData = images[0].svgData, let svg = SVG(data: svgData) {
						SVGView(svg: svg)
							.resizable()
							.aspectRatio(contentMode: .fit)
							.frame(width: halfWidth, height: halfHeight)
					}
				}
				HStack(spacing: spacing) {
					if let svgData = images[0].svgData, let svg = SVG(data: svgData) {
						SVGView(svg: svg)
							.resizable()
							.aspectRatio(contentMode: .fit)
							.frame(width: halfWidth, height: halfHeight)
					}
					if let svgData = images[0].svgData, let svg = SVG(data: svgData) {
						SVGView(svg: svg)
							.resizable()
							.aspectRatio(contentMode: .fit)
							.frame(width: halfWidth, height: halfHeight)
					}
				}
			}
		}
	}
}
