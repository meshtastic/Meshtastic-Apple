//
//  DeviceHardwareImage.swift
//  Meshtastic
//
//  Created by jake on 12/6/25.
//

import SwiftUI
import SwiftData
import SwiftDraw

// 1. THE LOADER (Public API)
// Responsibilities: Construct the Query only.
// It creates no heavy objects and runs no logic in init.
struct DeviceHardwareImage: View {
	
	@Query var hardwareResults: [DeviceHardwareEntity]
	
	// Init for Integer ID
	init<T>(hwId: T) where T: BinaryInteger {
		let hwModel = Int64(hwId)
		_hardwareResults = Query(filter: #Predicate<DeviceHardwareEntity> { hw in
			hw.hwModel == hwModel
		}, sort: [SortDescriptor(\.hwModelSlug)])
	}
	
	// Init for String Target
	init(platformioTarget: String) {
		_hardwareResults = Query(filter: #Predicate<DeviceHardwareEntity> { hw in
			hw.platformioTarget == platformioTarget
		}, sort: [SortDescriptor(\.hwModelSlug)])
	}
	
	var body: some View {
		// Pass the raw fetched results to the logic layer
		DeviceHardwareImageProcessor(hardware: hardwareResults)
	}
}

// 2. THE PROCESSOR (Internal)
// Responsibilities: Convert SwiftData Entities into a flat array of images.
// This uses .task to step out of the Layout Loop.
private struct DeviceHardwareImageProcessor: View {
	let hardware: [DeviceHardwareEntity]
	@EnvironmentObject var meshtasticAPI: MeshtasticAPI
	
	// We buffer the processed images in State.
	// This prevents the Layout pass from triggering faults.
	@State private var sortedImages: [DeviceHardwareImageEntity] = []
	
	var body: some View {
		DeviceHardwareImageLayout(
			images: sortedImages,
			isLoading: meshtasticAPI.isLoadingDeviceList
		)
		.task(id: hardware.count) {
			// Re-calculate only when the hardware list actually changes,
			// NOT when the scrollview bounces or layout shifts.
			self.sortedImages = processImages()
		}
	}
	
	// The heavy logic moved out of the computed property
	private func processImages() -> [DeviceHardwareImageEntity] {
		var returnImages = [DeviceHardwareImageEntity]()
		var seenFileNames = Set<String>()
		
		for item in hardware {
			for image in item.images {
				if image.svgData != nil {
					let name = image.fileName ?? ""
					if !seenFileNames.contains(name) {
						seenFileNames.insert(name)
						returnImages.append(image)
					}
				}
				if returnImages.count >= 4 { break }
			}
			if returnImages.count >= 4 { break }
		}
		
		return returnImages.sorted(by: { $0.fileName ?? "" < $1.fileName ?? "" })
	}
}

// 3. THE LAYOUT (Pure UI)
// Responsibilities: Draw boxes. No Core Data knowledge.
private struct DeviceHardwareImageLayout: View {
	let images: [DeviceHardwareImageEntity]
	let isLoading: Bool
	
	var body: some View {
		Color.clear
			.aspectRatio(1, contentMode: .fit)
			.overlay {
				if images.isEmpty {
					if isLoading {
						ProgressView()
					} else {
						Image("UNSET")
							.resizable()
							.scaledToFit()
					}
				} else {
					grid(images: images)
				}
			}
			.clipped() // Essential for ScrollView stability
	}
	
	@ViewBuilder
	private func grid(images: [DeviceHardwareImageEntity]) -> some View {
		let spacing: CGFloat = 10.0
		
		switch images.count {
		case 1:
			SingleImageView(entity: images[0])
			
		case 2:
			HStack(spacing: spacing) {
				SingleImageView(entity: images[0])
				SingleImageView(entity: images[1])
			}
			
		case 3:
			GeometryReader { proxy in
				HStack(spacing: spacing) {
					SingleImageView(entity: images[0])
						.frame(width: floor(proxy.size.width * 0.6))
					
					VStack(spacing: spacing) {
						SingleImageView(entity: images[1])
						SingleImageView(entity: images[2])
					}
				}
			}
			
		default: // 4 or more
			VStack(spacing: spacing) {
				HStack(spacing: spacing) {
					SingleImageView(entity: images[0])
					SingleImageView(entity: images[1])
				}
				HStack(spacing: spacing) {
					SingleImageView(entity: images[2])
					SingleImageView(entity: images[3])
				}
			}
		}
	}
}

// 4. THE LEAF VIEW
// Responsibilities: safely load SVG data
private struct SingleImageView: View {
	let entity: DeviceHardwareImageEntity
	@State private var svg: SVG?
	
	var body: some View {
		Group {
			if let svg = svg {
				SVGView(svg: svg)
					.resizable()
					.aspectRatio(contentMode: .fit)
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			} else {
				Color.clear
			}
		}
		.task {
			// Parse SVG once, prevents lag during scroll/layout
			if self.svg == nil, let data = entity.svgData {
				self.svg = SVG(data: data)
			}
		}
	}
}
