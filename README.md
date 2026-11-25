Google Cast Player
==================

A native macOS application that plays video files stored on your Mac on Chromecast
and Google TV devices.

The Mac remains the source of the media: files are streamed over the local network
through an integrated HTTP server and controlled through Google Cast. Nothing is
uploaded to a cloud service, and no external media server is involved.

Development status
------------------

The project is in **Phase 5 — Cast communication**. The application imports a
local video file, reports its name, container format, size, duration, resolution
and codecs, judges the format against the playback profile the app targets (MP4,
H.264, AAC), lists the Chromecast and Google TV devices on the local network,
and can open a session with a selected device: it connects over TLS, starts the
Default Media Receiver and reports the state the device confirms. A local HTTP
server can serve the selected file with byte-range support, and the client can
send a load command; wiring the two into a playback session is the next step.
The format verdict describes the file, not a device. See ROADMAP.md for the
phased plan and acceptance criteria.

Requirements
------------

* macOS 14 or later.
* Xcode 16 or later with the macOS SDK. The current project was created and
  verified with Xcode 27.2 and Swift 6.4.2.
* No third-party dependencies.
* Local network access, which macOS asks for the first time the app searches the
  network. Device discovery needs it; without it the app says so instead of
  returning an empty list.

Build, run and test
-------------------

The project uses a shared scheme named `GoogleCastPlayer`.

```sh
# Build the application
xcodebuild -project GoogleCastPlayer.xcodeproj -scheme GoogleCastPlayer \
  -configuration Debug -destination 'platform=macOS' build

# Run the automated tests
xcodebuild -project GoogleCastPlayer.xcodeproj -scheme GoogleCastPlayer \
  -configuration Debug -destination 'platform=macOS' test
```

You can also open `GoogleCastPlayer.xcodeproj` in Xcode and use the Run and Test actions.

Project layout
--------------

| Path | Purpose |
| --- | --- |
| `GoogleCastPlayer/` | Application sources: entry point, media import state, media model, SwiftUI screen. |
| `GoogleCastPlayerTests/` | Unit tests for the media model, the importer and the import state. |
| `GoogleCastPlayer.xcodeproj` | Xcode project with the application and unit test targets. |
| `ROADMAP.md` | Product vision, phases and acceptance criteria. |
| `DEVELOPMENT.md` | Verified development status, decisions and next objective. |
| `AGENTS.md` | Development workflow, quality requirements and autonomy boundaries. |

Architecture
------------

* `MediaFile` and `MediaFormat` describe the selected file and are independent of
  SwiftUI and of any media framework.
* `MediaImporter` validates a user-selected URL and produces a `MediaFile`.
* `MediaMetadataExtractor` reads duration, resolution and codecs with AVFoundation;
  `MediaCompatibilityEvaluator` judges those values against the target profile as a
  pure function, so the rules are testable without files.
* `SecurityScopedFileAccess` holds and releases the access to the selected file.
* `MediaImportModel` owns the import, access and metadata state. `DeviceDiscoveryModel`
  owns the discovered devices and the selection. Neither contains presentation logic.
* `CastDevice` describes a device found on the network; `BonjourCastDeviceBrowser`
  finds `_googlecast._tcp` services and reports appearances, changes and disappearances.
  Discovery never connects to a device.
* `LocalMediaServer` serves one file over HTTP with byte ranges, behind an
  unguessable path; `HTTPRequest` and `HTTPByteRange` hold the parsing rules and
  `LocalNetworkAddress` resolves the address a receiver can reach.
* `CastMessage`, `TLSCastTransport` and `CastClient` implement the Cast V2 protocol
  the app needs: message framing, the connection and heartbeat namespaces, receiver
  launch and the media load command. `CastConnectionModel` owns the session state
  the window shows.
* `MainScreen` renders the models and forwards user actions. It contains no
  validation, extraction, networking or protocol code.

Contribution workflow
---------------------

* `main` is stable and release ready, `dev` is the integration branch, and features
  are developed on `feature/<name>` branches created from the latest `main`.
* Completed features are integrated into `dev`; promoting `dev` to `main`, pushing,
  opening pull requests and releasing require explicit maintainer approval.
* Commits follow Conventional Commits.
* The optional pre-commit review gate runs `gga` (Gentleman Guardian Angel) against
  `AGENTS.md`. Install it with:

  ```sh
  cp .gga.example .gga   # set PROVIDER for your machine
  scripts/install-git-hooks.sh
  ```

  A failing review blocks the commit; the hook never skips the review silently.

License
-------

MIT. See LICENSE.
