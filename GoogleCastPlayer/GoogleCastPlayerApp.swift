import SwiftUI

@main
struct GoogleCastPlayerApp: App {
    @State private var mediaImportModel = MediaImportModel()
    @State private var deviceDiscoveryModel = DeviceDiscoveryModel()
    @State private var castConnectionModel = CastConnectionModel()

    var body: some Scene {
        Window("Google Cast Player", id: "main") {
            MainScreen(
                media: mediaImportModel,
                devices: deviceDiscoveryModel,
                connection: castConnectionModel
            )
        }
        .defaultSize(width: 700, height: 720)
    }
}
