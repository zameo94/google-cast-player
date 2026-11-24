Google Cast Player
==================

A native macOS application that plays video files stored on your Mac on Chromecast
and Google TV devices.

The Mac remains the source of the media: files are streamed over the local network
through an integrated HTTP server and controlled through Google Cast. Nothing is
uploaded to a cloud service, and no external media server is involved.

Development status
------------------

The project is in **Phase 1 — native application foundation and media import**.
The application currently imports a local video file, shows its name, container
format and size, and lets the user replace or remove the selection. Device
discovery, media serving, Cast communication and playback are not implemented yet;
see ROADMAP.md for the phased plan and acceptance criteria.

Requirements
------------

* macOS 14 or later.
* Xcode 16 or later with the macOS SDK. The current project was created and
  verified with Xcode 27.2 and Swift 6.4.2.
* No third-party dependencies.

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
* `MediaImporter` validates a user-selected URL and produces a `MediaFile`. It does
  not decode the container or assess Cast compatibility.
* `MediaImportModel` owns the import state and the current error. It contains no
  presentation logic.
* `MediaImportScreen` renders that state and forwards user actions. It contains no
  validation, networking or protocol code.

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
