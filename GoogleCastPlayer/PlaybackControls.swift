import SwiftUI

/// Transport controls for the active cast.
///
/// Everything shown here comes from what the receiver reports: the state label, the
/// play or pause button and the seek bar stay in step with the device, and a command is
/// only offered when the media session can accept it.
struct PlaybackControls: View {
    let device: CastDevice
    let connection: CastConnectionModel
    let playback: PlaybackModel

    @State private var seekTarget: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(statusTitle)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(statusColor)

                Spacer(minLength: 0)

                Button {
                    Task { await togglePlayback() }
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                }
                .disabled(!isControllable)
                .accessibilityLabel(isPlaying ? "Pause" : "Play")

                Button("Stop") {
                    Task { await playback.stopPlayback(connection: connection) }
                }
            }

            if let duration = connection.playbackSnapshot?.duration, duration > 0 {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack(spacing: 8) {
                        Text(Self.format(position(at: context.date)))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)

                        Slider(value: sliderValue(duration: duration), in: 0...duration) { isEditing in
                            if !isEditing {
                                commitSeek()
                            }
                        }
                        .accessibilityLabel("Playback position")

                        Text(Self.format(duration))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let url = playback.castingURL {
                Text(url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - State

    private var status: PlaybackSnapshot? {
        connection.playbackSnapshot
    }

    private var isPlaying: Bool {
        status?.status == .playing
    }

    private var isControllable: Bool {
        guard let status else {
            return false
        }
        return status.status == .playing
            || status.status == .paused
            || status.status == .buffering
    }

    private var statusTitle: String {
        switch status?.status {
        case .playing:
            return "Playing on \(device.name)"
        case .paused:
            return "Paused"
        case .buffering:
            return "Buffering\u{2026}"
        case .finished:
            return "Finished"
        case .failed:
            return "Playback failed"
        case .unknown, .none:
            return "Sent to \(device.name)"
        }
    }

    private var statusColor: Color {
        switch status?.status {
        case .playing:
            return .green
        case .failed:
            return .red
        case .finished:
            return .secondary
        case .none, .paused, .buffering, .unknown:
            return .secondary
        }
    }

    // MARK: - Actions

    private func togglePlayback() async {
        guard let status else {
            return
        }
        switch status.status {
        case .playing:
            await connection.pause()
        case .paused, .buffering:
            await connection.play()
        case .finished, .failed, .unknown:
            break
        }
    }

    private func position(at date: Date) -> TimeInterval {
        guard let status else {
            return 0
        }
        if let seekTarget {
            return seekTarget
        }
        let reported = status.position ?? 0
        guard status.status == .playing, let receivedAt = status.receivedAt else {
            return reported
        }
        let advanced = reported + date.timeIntervalSince(receivedAt)
        return min(advanced, status.duration ?? advanced)
    }

    private func sliderValue(duration: TimeInterval) -> Binding<Double> {
        Binding(
            get: { min(position(at: Date()), duration) },
            set: { seekTarget = $0 }
        )
    }

    private func commitSeek() {
        guard let target = seekTarget else {
            return
        }
        seekTarget = nil
        Task { await connection.seek(to: target) }
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remaining = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remaining)
        }
        return String(format: "%d:%02d", minutes, remaining)
    }
}
