import SwiftUI
import CoreData
import MeshtasticProtobufs

struct AudioMessageView: View {
    let message: MessageEntity
    let isCurrentUser: Bool

    // Share the singleton but track state per-message using currentlyPlayingMessageId
    @ObservedObject private var audioManager = AudioManager.shared

    /// True only when THIS message is the one currently playing
    private var isThisMessagePlaying: Bool {
        audioManager.currentlyPlayingMessageId == message.messageId && audioManager.isPlaying
    }

    var body: some View {
        HStack(spacing: 12) {
            // ── Left icon: play/pause, warning, or missed ──
            leadingIcon

            // ── Text + metadata / action buttons ──
            VStack(alignment: .leading, spacing: 4) {
                titleView

                subtitleView
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(bubbleBackground)
        .cornerRadius(15)
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var leadingIcon: some View {
        if message.audioData == nil {
            // Completely missed — no chunks arrived at all
            Image(systemName: "waveform.slash")
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .foregroundColor(isCurrentUser ? .white.opacity(0.8) : .secondary)
                .accessibilityLabel("Voice message missed")
        } else if message.partialAudioInfo != nil {
            // Partial — some chunks are missing
            Image(systemName: "exclamationmark.triangle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .foregroundColor(isCurrentUser ? .white : .orange)
                .accessibilityLabel("Partial voice message")
        } else {
            // Full audio — show play/pause for THIS message only
            Button {
                if isThisMessagePlaying {
                    audioManager.stopPlayback()
                } else {
                    // Stop any other message first
                    if audioManager.isPlaying { audioManager.stopPlayback() }
                    if let data = message.audioData {
                        audioManager.playAudio(codec2Data: data, messageId: message.messageId)
                    }
                }
            } label: {
                Image(systemName: isThisMessagePlaying ? "pause.circle.fill" : "play.circle.fill")
                    .resizable()
                    .frame(width: 32, height: 32)
                    .foregroundColor(isCurrentUser ? .white : .accentColor)
                    .animation(.easeInOut(duration: 0.15), value: isThisMessagePlaying)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isThisMessagePlaying ? "Pause voice message" : "Play voice message")
            .accessibilityAddTraits(.allowsDirectInteraction)
        }
    }

    @ViewBuilder
    private var titleView: some View {
        if message.audioData == nil {
            Text("Voice Message (Missed)")
                .font(.body).fontWeight(.medium)
                .foregroundColor(isCurrentUser ? .white : .primary)
        } else if message.partialAudioInfo != nil {
            Text("Partial Voice Message")
                .font(.body).fontWeight(.medium)
                .foregroundColor(isCurrentUser ? .white : .primary)
        } else {
            Text("Voice Message")
                .font(.body).fontWeight(.medium)
                .foregroundColor(isCurrentUser ? .white : .primary)
        }
    }

    @ViewBuilder
    private var subtitleView: some View {
        if message.audioData == nil {
            // Fully missed: show request button
            requestButton(label: "Request Audio", startChunk: 0, audioId: nil)
        } else if let partial = message.partialAudioInfo {
            // Partial: show progress + request button
            let progress = Double(partial.chunks.count) / Double(partial.total)
            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle(tint: isCurrentUser ? .white : .orange))
                .scaleEffect(x: 1, y: 2, anchor: .center)

            Text("\(partial.chunks.count) of \(partial.total) parts received")
                .font(.caption)
                .foregroundColor(isCurrentUser ? .white.opacity(0.8) : .secondary)

            requestButton(label: "Request Missing", startChunk: firstMissingChunk(partial), audioId: partial.id)
        } else if let data = message.audioData {
            // At 1400bps: 8 bytes/frame × 40ms/frame → 1 second per 200 bytes
            let durationSec = max(1, Int((Double(data.count) / 200.0).rounded()))
            Text(durationSec == 1 ? "~1s voice message" : "~\(durationSec)s voice message")
                .font(.caption)
                .foregroundColor(isCurrentUser ? .white.opacity(0.8) : .secondary)
        }
    }

    // MARK: - Request button

    private func requestButton(label: String, startChunk: Int, audioId: UInt16?) -> some View {
        Button {
            sendResendRequest(startChunk: startChunk, audioId: audioId)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.clockwise")
                    .font(.caption2)
                Text(label)
                    .font(.caption2)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isCurrentUser ? Color.white.opacity(0.25) : Color.orange)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func firstMissingChunk(_ partial: PartialVoiceInfo) -> Int {
        for i in 0..<partial.total where partial.chunks[i] == nil {
            return i
        }
        return -1
    }

    private var bubbleBackground: some View {
        Group {
            if isCurrentUser {
                Color.accentColor
            } else {
                Color.gray.opacity(0.2)
            }
        }
    }

    private func sendResendRequest(startChunk: Int, audioId: UInt16?) {
        let id: UInt16
        if let audioId = audioId {
            id = audioId
        } else {
            // For a fully-missed message we derive the ID from the packet messageId
            id = UInt16(truncatingIfNeeded: message.messageId)
        }

        Task {
            var reqPayload = Data([
                0xc0, 0xde, 0xc2, 0xff,
                UInt8(id >> 8), UInt8(id & 0xff),
                UInt8(startChunk)
            ])
            var dataMessage = DataMessage()
            dataMessage.payload = reqPayload
            dataMessage.portnum = PortNum.audioApp

            var meshPkt = MeshPacket()
            // We are the recipient requesting from the sender, so from = our node (toUser), to = sender (fromUser)
            meshPkt.from = UInt32(message.toUser?.num ?? 0)
            meshPkt.to   = UInt32(message.fromUser?.num ?? 0)
            meshPkt.channel = UInt32(message.channel)
            meshPkt.decoded = dataMessage
            meshPkt.wantAck = true

            var toRadio = ToRadio()
            toRadio.packet = meshPkt
            try? await AccessoryManager.shared.send(
                toRadio,
                debugDescription: "🎙️ Requesting audio (id=\(id)) from chunk \(startChunk)"
            )
        }
    }
}
