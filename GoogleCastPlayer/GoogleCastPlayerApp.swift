import SwiftUI

@main
struct GoogleCastPlayerApp: App {
    @State private var mediaImportModel = MediaImportModel()
    @State private var deviceDiscoveryModel = DeviceDiscoveryModel()

    var body: some Scene {
        Window("Google Cast Player", id: "main") {
            MainScreen(media: mediaImportModel, devices: deviceDiscoveryModel)
        }
        .defaultSize(width: 700, height: 720)
    }
}
