import SwiftUI

@main
struct GoogleCastPlayerApp: App {
    @State private var mediaImportModel = MediaImportModel()

    var body: some Scene {
        Window("Google Cast Player", id: "main") {
            MediaImportScreen(model: mediaImportModel)
        }
        .defaultSize(width: 640, height: 520)
    }
}
