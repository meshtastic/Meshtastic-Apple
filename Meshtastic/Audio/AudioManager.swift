import Foundation
import AVFoundation
import OSLog

@MainActor
class AudioManager: NSObject, ObservableObject, AVAudioRecorderDelegate {
    static let shared = AudioManager()

    @Published var isRecording = false
    @Published var isPlaying = false
    @Published var currentlyPlayingMessageId: Int64? = nil
    @Published var recordingDuration: TimeInterval = 0

    // Config based on typical Codec2 needs (8kHz, 16-bit PCM, mono)
    private let sampleRate: Double = 8000

    private var audioRecorder: AVAudioRecorder?
    private var audioEngine: AVAudioEngine?
    private var audioPlayerNode: AVAudioPlayerNode?
    private var recordingTimer: Timer?
    private var codec: Codec2?

    private var recordingURL: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("temp_voice_memo.wav")
    }

    override init() {
        super.init()
        setupAudioSession()
        // Meshtastic using 1400bps (mode 3)
        codec = Codec2(mode: .init(rawValue: 3) ?? ._1400)
    }

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: .defaultToSpeaker)
            try session.setActive(true)
        } catch {
            Logger.services.error("Failed to setup audio session: \(error)")
        }
    }

    func startRecording() {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]
        do {
            audioRecorder = try AVAudioRecorder(url: recordingURL, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.prepareToRecord()
            audioRecorder?.record()
            isRecording = true
            recordingDuration = 0

            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self, let recorder = self.audioRecorder else { return }
                self.recordingDuration = recorder.currentTime
            }
        } catch {
            Logger.services.error("Failed to start recording: \(error)")
        }
    }

    func cancelRecording() {
        stopRecordingCleanup()
        if FileManager.default.fileExists(atPath: recordingURL.path) {
            try? FileManager.default.removeItem(at: recordingURL)
        }
    }

    func stopRecordingAndEncode() -> Data? {
        stopRecordingCleanup()
        guard let c = codec else { return nil }
        guard let rawData = try? Data(contentsOf: recordingURL) else {
            Logger.services.error("Failed to read recorded PCM audio")
            return nil
        }

        // Convert raw WAV bytes to Int16 samples (skip 44-byte WAV header)
        let headerSize = 44
        guard rawData.count > headerSize else { return nil }
        let pcmData = rawData.dropFirst(headerSize)

        let samplesPerFrame = c.samplesPerFrame
        var allEncodedBytes = Data()

        // Process frame by frame
        Logger.audio.info("🎙️ Starting raw audio to Codec2 Encoding. PCM Size: \(pcmData.count) bytes")
        var offset = 0
        let rawBytes = Array(pcmData)
        while offset + samplesPerFrame * 2 <= rawBytes.count {
            var frame = [Int16](repeating: 0, count: samplesPerFrame)
            for i in 0..<samplesPerFrame {
                let lo = UInt16(rawBytes[offset + i * 2])
                let hi = UInt16(rawBytes[offset + i * 2 + 1])
                frame[i] = Int16(bitPattern: lo | (hi << 8))
            }
            let encoded = c.encode(speech: &frame)
            allEncodedBytes.append(contentsOf: encoded)
            offset += samplesPerFrame * 2
        }
        
        // Enforce rolling buffer limit of 1000 bytes (up to 5 chunks of 200 bytes)
        let maxPayloadSize = 1000
        let bytesPerFrame = c.bytesPerEncFrame
        let maxFrames = maxPayloadSize / bytesPerFrame
        let maxBytes = maxFrames * bytesPerFrame

        if allEncodedBytes.count > maxBytes {
            let overflow = allEncodedBytes.count - maxBytes
            allEncodedBytes.removeFirst(overflow)
            Logger.audio.info("🎙️ Rolling buffer limit applied. Dropped earliest \(overflow) bytes.")
        }
        
        Logger.audio.info("🎙️ Audio Encoding Complete. Codec2 payload generated size: \(allEncodedBytes.count) bytes")
        return allEncodedBytes.isEmpty ? nil : allEncodedBytes
    }

    private func stopRecordingCleanup() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        audioRecorder?.stop()
        isRecording = false
    }

    // Play back codec2 encoded audio
    func playAudio(codec2Data: Data, messageId: Int64 = 0) {
        guard !isPlaying, let c = codec else { return }

        let bytes = Array(codec2Data)
        let bytesPerFrame = c.bytesPerEncFrame
        Logger.audio.info("🎙️ Play audio decoder invoked. Codec2 encoded length: \(bytes.count) bytes")
        guard bytesPerFrame > 0, bytes.count >= bytesPerFrame else { return }

        // Decode all frames to Int16
        var allSamples = [Int16]()
        var offset = 0
        while offset + bytesPerFrame <= bytes.count {
            var frame = Array(bytes[offset..<offset + bytesPerFrame])
            let decoded = c.decode(frame: &frame)
            allSamples.append(contentsOf: decoded)
            offset += bytesPerFrame
        }

        Logger.audio.info("🎙️ Audio Codec2 Decoder Complete. Total decompressed PCM samples: \(allSamples.count)")
        guard !allSamples.isEmpty else { return }

        // Convert Int16 samples to Float32 (AVAudioEngine requires Float32 non-interleaved)
        let floatSamples: [Float] = allSamples.map { Float($0) / 32768.0 }

        audioEngine = AVAudioEngine()
        audioPlayerNode = AVAudioPlayerNode()
        guard let engine = audioEngine, let player = audioPlayerNode else { return }

        // Use Float32 non-interleaved — the only format reliably supported by AVAudioEngine
        guard let audioFormat = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 1
        ) else {
            Logger.services.error("Failed to create audio format for playback")
            return
        }

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: audioFormat)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: AVAudioFrameCount(floatSamples.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(floatSamples.count)

        let channelData = buffer.floatChannelData!
        floatSamples.withUnsafeBufferPointer { ptr in
            channelData[0].assign(from: ptr.baseAddress!, count: floatSamples.count)
        }

        do {
            try engine.start()
            isPlaying = true
            currentlyPlayingMessageId = messageId

            player.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
                DispatchQueue.main.async {
                    self?.isPlaying = false
                    self?.currentlyPlayingMessageId = nil
                    self?.audioEngine?.stop()
                }
            }
            player.play()
        } catch {
            Logger.services.error("Failed to start audio engine for playback: \(error)")
            isPlaying = false
            currentlyPlayingMessageId = nil
        }
    }

    func stopPlayback() {
        audioPlayerNode?.stop()
        audioEngine?.stop()
        isPlaying = false
        currentlyPlayingMessageId = nil
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            stopRecordingCleanup()
        }
    }
}
