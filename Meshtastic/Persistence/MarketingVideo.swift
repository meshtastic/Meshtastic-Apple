//
//  MarketingVideo.swift
//  Meshtastic
//
//   Copyright(c) Garth Vander Houwen 9/2/26.
//

#if DEBUG
import AVFoundation
import OSLog
#if canImport(UIKit)
import UIKit
#endif

/// Records the app window to an H.264 file for an App Store app preview.
///
/// The screen is captured in process rather than by `screencapture` or ReplayKit: the driving
/// script may have no Screen Recording permission, and neither does CI. On Mac Catalyst
/// `drawHierarchy` does capture the Metal-backed map — the thing that made this approach fail on
/// tvOS, where the same call rendered the map black.
///
/// Frames are stamped with real elapsed time, so the file plays back at the speed the flyover
/// actually ran even when capture cannot keep up with the requested rate.
@MainActor
final class MarketingVideoRecorder {
	private let writer: AVAssetWriter
	private let input: AVAssetWriterInput
	private let size: CGSize
	private let started = CACurrentMediaTime()
	private var frames = 0
	private var finished = false
	/// App previews are specified at 30fps. Capturing a 2560x1600 window costs ~95ms a frame, so
	/// the source is nearer 10fps: hold a 30fps timeline and repeat the newest frame into the slots
	/// capture could not fill. Motion is as smooth as the capture allowed, but the file is 30fps
	/// and its duration matches the recording.
	private static let frameRate = 30
	private var nextSlot = 0

	/// - Parameters:
	///   - size: Output pixel size. Must match an App Store preview size for the target device.
	///   - url: Destination file; an existing file at the path is replaced.
	init?(size: CGSize, url: URL) {
		try? FileManager.default.removeItem(at: url)
		guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return nil }
		let settings: [String: Any] = [
			AVVideoCodecKey: AVVideoCodecType.h264,
			AVVideoWidthKey: Int(size.width),
			AVVideoHeightKey: Int(size.height)
		]
		let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
		input.expectsMediaDataInRealTime = true
		guard writer.canAdd(input) else { return nil }
		writer.add(input)
		guard writer.startWriting() else { return nil }
		writer.startSession(atSourceTime: .zero)
		self.writer = writer
		self.input = input
		self.size = size
	}

	/// Append one frame, filling every 30fps slot up to now with it. Drops the frame if the writer
	/// is not ready rather than stalling the UI.
	func append(_ image: UIImage) {
		guard !finished, input.isReadyForMoreMediaData, let cgImage = image.cgImage else { return }
		guard let buffer = Self.pixelBuffer(from: cgImage, size: size) else { return }
		let elapsed = CACurrentMediaTime() - started
		let targetSlot = max(Int(elapsed * Double(Self.frameRate)), nextSlot)
		while nextSlot <= targetSlot {
			let time = CMTime(value: CMTimeValue(nextSlot), timescale: CMTimeScale(Self.frameRate))
			guard let sample = Self.sampleBuffer(from: buffer, at: time) else { break }
			input.append(sample)
			frames += 1
			nextSlot += 1
			// Stop filling if the writer needs to drain; the next call picks up where this left off.
			if !input.isReadyForMoreMediaData { break }
		}
	}

	/// Finish the file and report where it landed and how many frames it holds.
	func finish() async -> (url: URL, frames: Int, seconds: Double) {
		guard !finished else { return (writer.outputURL, frames, CACurrentMediaTime() - started) }
		finished = true
		let seconds = CACurrentMediaTime() - started
		input.markAsFinished()
		await writer.finishWriting()
		if let error = writer.error {
			Logger.data.error("🎬 [Marketing] Video write failed: \(error.localizedDescription, privacy: .public)")
		}
		return (writer.outputURL, frames, seconds)
	}

	// The adaptor's own pool comes back nil for large frames, so allocate buffers directly —
	// the same problem the tvOS recorder hit.
	private static func pixelBuffer(from cgImage: CGImage, size: CGSize) -> CVPixelBuffer? {
		let attributes: [CFString: Any] = [
			kCVPixelBufferCGImageCompatibilityKey: true,
			kCVPixelBufferCGBitmapContextCompatibilityKey: true
		]
		var buffer: CVPixelBuffer?
		let status = CVPixelBufferCreate(
			kCFAllocatorDefault, Int(size.width), Int(size.height),
			kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer
		)
		guard status == kCVReturnSuccess, let buffer else { return nil }
		CVPixelBufferLockBaseAddress(buffer, [])
		defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
		guard let context = CGContext(
			data: CVPixelBufferGetBaseAddress(buffer),
			width: Int(size.width), height: Int(size.height),
			bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
			space: CGColorSpaceCreateDeviceRGB(),
			bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
		) else { return nil }
		context.draw(cgImage, in: CGRect(origin: .zero, size: size))
		return buffer
	}

	private static func sampleBuffer(from pixelBuffer: CVPixelBuffer, at time: CMTime) -> CMSampleBuffer? {
		var format: CMVideoFormatDescription?
		guard CMVideoFormatDescriptionCreateForImageBuffer(
			allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &format
		) == noErr, let format else { return nil }
		var timing = CMSampleTimingInfo(
			duration: .invalid, presentationTimeStamp: time, decodeTimeStamp: .invalid
		)
		var sample: CMSampleBuffer?
		guard CMSampleBufferCreateReadyWithImageBuffer(
			allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
			formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample
		) == noErr else { return nil }
		return sample
	}
}
#endif
