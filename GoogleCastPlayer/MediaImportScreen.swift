import SwiftUI
import UniformTypeIdentifiers

/// Main window content: import one local video file and present what is known about it.
///
/// The view renders model state and forwards user actions. It contains no file
/// validation, no metadata extraction and no Cast or media-serving behaviour.
struct MediaImportScreen: View {
    let model: MediaImportModel

    @State private var isFilePickerPresented = false
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            if let selectedFile = model.selectedFile {
                selectedFileCard(selectedFile)
            } else {
                dropArea
            }

            if let errorMessage = model.errorMessage {
                errorBanner(errorMessage)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 420, alignment: .topLeading)
        .task(id: model.selectedFile?.id) {
            await model.loadMetadata()
        }
        .fileImporter(
            isPresented: $isFilePickerPresented,
            allowedContentTypes: [.movie],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                Task { @MainActor in
                    model.importFiles(at: urls)
                }
            case let .failure(error):
                Task { @MainActor in
                    model.reportFilePickerFailure(error)
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            Task { @MainActor in
                model.importFiles(at: urls)
            }
            return true
        } isTargeted: { isTargeted in
            Task { @MainActor in
                isDropTargeted = isTargeted
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Google Cast Player")
                .font(.largeTitle.weight(.semibold))
            Text("Play video files from your Mac on Chromecast and Google TV devices.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

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
        .frame(maxWidth: .infinity, minHeight: 240)
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
                    model.removeSelection()
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
        switch model.metadataState {
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
                model.dismissError()
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
