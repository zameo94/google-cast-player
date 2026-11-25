Google Cast Player
==================

A native macOS application that plays video files stored on your Mac on Chromecast
and Google TV devices.

The Mac remains the source of the media: files are streamed over the local network
through an integrated HTTP server and controlled through Google Cast. Nothing is
uploaded to a cloud service, and no external media server is involved.

Development status
------------------

The project is in **Phase 8 — stabilization and release candidate**. The application imports a local
video file, reports its name, container format, size, duration, resolution and codecs,
judges the format against the playback profile the app targets (MP4, H.264, AAC),
lists the Chromecast and Google TV devices on the local network, and can open a
session with a selected device: it connects over TLS, starts the Default Media
Receiver and reports the state the device confirms. Casting a video starts the local
HTTP server for that file and hands the URL to the device, so the receiver fetches the
media directly from the Mac.

Play, pause and seek, together with the state the device reports, are implemented on
the playback-controls branch and are covered by tests; they still need a hardware
check before they count as verified. Stopping the cast closes the server. See
ROADMAP.md for the phased plan and acceptance criteria.

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
| `GoogleCastPlayerTests/` | Tests for the media model and importer, metadata, discovery, the HTTP server, the Cast protocol and the playback orchestration. |
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
  the window shows, and `PlaybackModel` owns the server lifetime while a cast runs.
* `MainScreen` renders the models and forwards user actions. It contains no
  validation, extraction, networking or protocol code.

Installation
------------

The MVP is built from source; there is no notarized distribution yet.

1. Install Xcode 16 or later (verified with Xcode 27.2).
2. Open `GoogleCastPlayer.xcodeproj`, choose the `GoogleCastPlayer` scheme and press
   Run, or build it from the command line:

   ```sh
   xcodebuild -project GoogleCastPlayer.xcodeproj -scheme GoogleCastPlayer \
     -configuration Release -destination 'platform=macOS' build
   ```

The built application is ad-hoc signed for local use. Shipping a signed, notarized
build is part of the release work that still needs the maintainer's approval.

Permissions
-----------

* **Local network**: needed to find Cast devices and to let a receiver fetch the file.
  macOS asks the first time the app searches; if it was denied, the app says so instead
  of showing an empty list. It can be re-enabled in System Settings > Privacy &
  Security > Local Network.
* No camera, microphone, contacts, or photo access is requested. The app reads only the
  file the user selects.

Supported formats
-----------------

* Target profile: MP4 container with H.264 video and AAC audio.
* MOV is reported as "may not be compatible" because MP4 is the prioritized container.
* Other containers (MKV, AVI, WebM) and codecs (HEVC on older receivers, VP9, ALAC) are
  reported as unsupported or device-dependent. There is no transcoding: a file that the
  receiver cannot decode is reported, not converted.

Security and privacy
--------------------

* Files never leave the local network and are never uploaded; there is no cloud
  component, no account, and no analytics.
* The HTTP server runs only while a cast is active, serves only the selected file, and
  exposes it under an unguessable per-session path. Every other path answers 404, so the
  file system is not reachable. Requests are size-capped, malformed requests are
  rejected, and the server stops when the cast ends.
* The server speaks plain HTTP with no authentication beyond the path: it is meant for a
  trusted local network. Do not cast on a network you do not trust.
* The TLS connection to the device accepts the device's self-signed certificate, which
  is what Cast devices present; trust comes from the local network, not from a
  certificate chain.

Sleep, screen lock and the display
----------------------------------

While a cast is running the application holds a macOS activity assertion: the Mac is kept
out of App Nap, which otherwise coalesces timers and throttles network I/O once the window
is inactive, and out of idle sleep. Locking the screen, letting the display turn off, or
leaving the window in the background therefore does not end the cast: the media server and
the connection to the device stay alive.

Closing the lid is different. macOS always puts the Mac to sleep on lid close and no
application can override that, so the device stops when the Mac sleeps. When the Mac
wakes, the application reconnects to the device and resumes the video from the last
position the device reported. If that attempt fails, the playback section offers Resume
and Stop instead of pretending the session is still running.

A session that drops while the Mac is awake is recovered the same way: the application
keeps the Mac awake, reconnects and reloads the file where the device stopped, retrying
three times. It releases the wake lock only when recovery gives up, so a short network
loss cannot put the Mac to sleep before the recovery had a chance to run.

Every step of that lifecycle is written to the unified log, which is where to look when a
session ends hours later:

    log show --last 2h --info --predicate 'subsystem == "io.github.zameo94.GoogleCastPlayer"'

`--info` is needed because those messages are informational; without it only errors and
faults appear. The same entries can be watched live in Console.app by filtering on the
subsystem, or with `log stream --level info --predicate 'subsystem == "io.github.zameo94.GoogleCastPlayer"'.

The assertion can be checked from a terminal while a cast is running:

    pmset -g assertions

Two system-level options keep the Mac awake with the lid closed. Both are decisions the
user makes outside the application, and neither is required while the lid is open:

* Clamshell mode: connect a charger and an external display; macOS then keeps running with
  the lid closed.
* A system-wide sleep override, which also applies to every other application and costs
  battery life and heat:

      sudo pmset -a disablesleep 1    # revert with: sudo pmset -a disablesleep 0

Known limitations
-----------------

* No transcoding: MKV, AVI and MOV files are not castable, and HEVC depends on the
  receiver model.
* The compatibility verdict describes the container and codecs of the file; it does not
  promise playback on a specific device.
* The displayed playback position is interpolated between status updates and can drift
  by about a second.
* While the Mac is asleep, for example with the lid closed, the cast stops. It resumes
  automatically after the wake, but the video does not keep playing through the sleep.

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
