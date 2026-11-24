import Testing
@testable import GoogleCastPlayer

struct MediaFormatTests {
    @Test func displayNameUppercasesTheExtension() {
        #expect(MediaFormat(fileExtension: "mp4").displayName == "MP4")
        #expect(MediaFormat(fileExtension: "mov").displayName == "MOV")
    }

    @Test func displayNameReportsMissingExtension() {
        #expect(MediaFormat(fileExtension: nil).displayName == "Unknown format")
        #expect(MediaFormat(fileExtension: "").displayName == "Unknown format")
    }
}
