import SwiftUI
import UniformTypeIdentifiers

/// Main window content: import one local video file and present the selection.
///
/// The view renders model state and forwards user actions. It contains no file
/// validation and no Cast or media-serving behaviour.
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
                    Text(detailLine(for: selectedFile))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

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

    private func detailLine(for selectedFile: MediaFile) -> String {
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
