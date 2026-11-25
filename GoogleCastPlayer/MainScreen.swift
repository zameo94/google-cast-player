import SwiftUI
import UniformTypeIdentifiers

/// Main window content: choose one video file and one Cast device.
///
/// The view renders model state and forwards user actions. It contains no file
/// validation, no metadata extraction and no networking.
struct MainScreen: View {
    let media: MediaImportModel
    let devices: DeviceDiscoveryModel
    let connection: CastConnectionModel
    let playback: PlaybackModel

    @State private var isFilePickerPresented = false
    @State private var isDropTargeted = false
    @State private var searchID = UUID()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if let selectedFile = media.selectedFile {
                    selectedFileCard(selectedFile)
                } else {
                    dropArea
                }

                if let errorMessage = media.errorMessage {
                    errorBanner(errorMessage)
                }

                deviceSection

                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 560, minHeight: 560)
        .task(id: media.selectedFile?.id) {
            await media.loadMetadata()
        }
        .task(id: searchID) {
            await devices.run()
        }
        .onChange(of: devices.selectedDeviceID) {
            Task { await connection.disconnect() }
        }
        .onChange(of: connection.state) { _, newState in
            if newState != .connected {
                playback.stop()
            }
        }
        .fileImporter(
            isPresented: $isFilePickerPresented,
            allowedContentTypes: [.movie],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                Task { @MainActor in
                    media.importFiles(at: urls)
                }
            case let .failure(error):
                Task { @MainActor in
                    media.reportFilePickerFailure(error)
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            Task { @MainActor in
                media.importFiles(at: urls)
            }
            return true
        } isTargeted: { isTargeted in
            Task { @MainActor in
                isDropTargeted = isTargeted
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Google Cast Player")
                .font(.largeTitle.weight(.semibold))
            Text("Play video files from your Mac on Chromecast and Google TV devices.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Video

    private var dropArea: some View {
        VStack(spacing: 12) {
            Image(systemName: "film.stack")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("No video selected")
                .font(.headline)

            Text("Drag a video file here, or choose one from your Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Choose Video\u{2026}") {
                isFilePickerPresented = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut("o")
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.quinary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [6, 4])
                )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Video drop area")
    }

    private func selectedFileCard(_ selectedFile: MediaFile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "film")
                    .font(.system(size: 26))
                    .foregroundStyle(.tint)
                    .frame(width: 32)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedFile.name)
                        .font(.headline)
                        .lineLimit(2)
                        .textSelection(.enabled)
                    Text(sizeLine(for: selectedFile))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            metadataSection

            HStack(spacing: 12) {
                Button("Choose Different Video\u{2026}") {
                    isFilePickerPresented = true
                }
                .keyboardShortcut("o")

                Button("Remove", role: .destructive) {
                    media.removeSelection()
                }

                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.quinary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.25),
                    lineWidth: isDropTargeted ? 2 : 1
                )
        )
    }

    @ViewBuilder
    private var metadataSection: some View {
        switch media.metadataState {
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Reading media information\u{2026}")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case let .available(metadata, compatibility):
            VStack(alignment: .leading, spacing: 6) {
                compatibilityLabel(compatibility)

                Text(metadata.summaryLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if let audioLine = metadata.audioLine {
                    Text(audioLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(compatibility.reasons.indices, id: \.self) { index in
                    Text(compatibility.reasons[index])
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case let .unavailable(message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        case .none:
            EmptyView()
        }
    }

    private func compatibilityLabel(_ compatibility: MediaCompatibility) -> some View {
        let descriptor = compatibility.descriptor
        return Label(descriptor.title, systemImage: descriptor.symbolName)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(descriptor.color)
            .accessibilityLabel("Compatibility: \(descriptor.title)")
    }

    private func sizeLine(for selectedFile: MediaFile) -> String {
        let size = selectedFile.byteCount.formatted(.byteCount(style: .file))
        return "\(selectedFile.format.displayName) \u{00B7} \(size)"
    }

    // MARK: - Devices

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Device")
                    .font(.headline)

                Spacer(minLength: 0)

                if devices.state == .searching {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Searching\u{2026}")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            switch devices.state {
            case .searching, .ready:
                if devices.devices.isEmpty {
                    emptyDeviceList
                } else {
                    VStack(spacing: 8) {
                        ForEach(devices.devices) { device in
                            deviceCard(device)
                        }
                    }
                }
            case let .failed(message):
                failedDeviceList(message)
            }

            if let selectedDevice = devices.selectedDevice {
                connectionRow(selectedDevice)
                playbackRow(selectedDevice)
            }

            Text("A blue card is selected, a green card is connected. Casting serves the file from this Mac over the local network; pause, seek and reported playback state arrive in the next step.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.quinary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
        )
    }

    private var emptyDeviceList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No Cast device found yet. Make sure the device is on the same network.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Search Again") {
                searchID = UUID()
            }
        }
    }

    private func failedDeviceList(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Search Again") {
                searchID = UUID()
            }
        }
    }

    private func deviceCard(_ device: CastDevice) -> some View {
        let isSelected = devices.selectedDeviceID == device.id
        let isConnected = connection.state == .connected && connection.connectedDevice?.id == device.id
        let isConnecting = connection.state == .connecting && connection.connectedDevice?.id == device.id

        return HStack(spacing: 12) {
            Button {
                devices.selectDevice(id: device.id)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "tv")
                        .font(.system(size: 18))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .frame(width: 24)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name)
                            .font(.body.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(.primary)
                        if let modelName = device.modelName {
                            Text(modelName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(device.name)
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            deviceCardAction(device, isSelected: isSelected, isConnecting: isConnecting)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(cardFill(isSelected: isSelected, isConnected: isConnected))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    cardBorder(isSelected: isSelected, isConnected: isConnected),
                    lineWidth: isSelected || isConnected ? 2 : 1
                )
        )
    }

    @ViewBuilder
    private func deviceCardAction(
        _ device: CastDevice,
        isSelected: Bool,
        isConnecting: Bool
    ) -> some View {
        if isConnecting {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Connecting")
        } else if isSelected {
            Button("Connect") {
                Task { await connection.connect(to: device) }
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private func connectionRow(_ device: CastDevice) -> some View {
        switch connection.state {
        case .idle:
            EmptyView()
        case .connecting:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Connecting\u{2026}")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Cancel") {
                    Task { await connection.disconnect() }
                }
            }
        case .connected:
            HStack(spacing: 8) {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color.green)
                Spacer(minLength: 0)
                Button("Disconnect") {
                    Task { await connection.disconnect() }
                }
            }
        case let .failed(message):
            VStack(alignment: .leading, spacing: 6) {
                Label("Not connected", systemImage: "xmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color.red)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button("Try Again") {
                        Task { await connection.connect(to: device) }
                    }
                    Button("Dismiss") {
                        Task { await connection.disconnect() }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func playbackRow(_ device: CastDevice) -> some View {
        if connection.state == .connected {
            switch playback.state {
            case .idle:
                VStack(alignment: .leading, spacing: 4) {
                    Button("Play on \(device.name)") {
                        startCasting()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(media.selectedFile == nil)

                    if media.selectedFile == nil {
                        Text("Choose a video first.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            case .starting:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Starting\u{2026}")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            case let .casting(url):
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Label("Sent to \(device.name)", systemImage: "airplayvideo")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(Color.green)
                        Spacer(minLength: 0)
                        Button("Stop") {
                            Task { await playback.stopPlayback(connection: connection) }
                        }
                    }
                    Text(url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            case let .failed(message):
                VStack(alignment: .leading, spacing: 6) {
                    Label("Casting failed", systemImage: "xmark.circle.fill")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color.red)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Stop") {
                        Task { await playback.stopPlayback(connection: connection) }
                    }
                }
            }
        }
    }

    private func startCasting() {
        guard let file = media.selectedFile else {
            return
        }
        Task {
            await playback.play(file: file, connection: connection)
        }
    }

    private func cardFill(isSelected: Bool, isConnected: Bool) -> Color {
        if isConnected {
            return Color.green.opacity(0.14)
        }
        return isSelected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.08)
    }

    private func cardBorder(isSelected: Bool, isConnected: Bool) -> Color {
        if isConnected {
            return .green
        }
        return isSelected ? Color.accentColor : Color.secondary.opacity(0.2)
    }

    // MARK: - Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Button("Dismiss") {
                media.dismissError()
            }
            .buttonStyle(.link)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(0.12))
        )
    }
}

private extension MediaMetadata {
    /// One line describing duration, resolution and video codec when known.
    var summaryLine: String {
        var parts: [String] = []
        if let duration {
            parts.append(duration >= .seconds(3600)
                ? duration.formatted(.time(pattern: .hourMinuteSecond))
                : duration.formatted(.time(pattern: .minuteSecond)))
        }
        if let track = videoTracks.first {
            parts.append(track.codec.displayName)
            parts.append("\(track.width) \u{00D7} \(track.height)")
        } else {
            parts.append("No video track reported")
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    /// One line describing the audio, or `nil` when the file reports no audio track.
    var audioLine: String? {
        guard !audioTracks.isEmpty else {
            return "No audio track"
        }
        let codecs = audioTracks.map(\.codec.displayName).joined(separator: ", ")
        return "Audio: \(codecs)"
    }
}

private extension MediaCompatibility {
    struct Descriptor {
        let title: String
        let symbolName: String
        let color: Color
    }

    var descriptor: Descriptor {
        switch status {
        case .compatible:
            return Descriptor(title: "Format supported", symbolName: "checkmark.circle.fill", color: .green)
        case .uncertain:
            return Descriptor(title: "May not be compatible", symbolName: "questionmark.circle.fill", color: .orange)
        case .unsupported:
            return Descriptor(title: "Not supported", symbolName: "xmark.circle.fill", color: .red)
        }
    }
}
