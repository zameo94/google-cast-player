# Google Cast Player

A native macOS application that plays video files stored on your Mac on Chromecast and
Google TV devices. The Mac stays the source of the media: the file is served over the
local network by an HTTP server inside the app and the device plays it, so nothing is
uploaded and no media server has to run anywhere.

The code in this repository was written by coding agents under human direction. The idea,
the architecture, the product decisions and every verification on real hardware were
human work.

---

## Table of contents

- [How it was built](#how-it-was-built)
- [Requirements](#requirements)
- [Installation](#installation)
- [Tested devices](#tested-devices)
- [How it works](#how-it-works)
- [Technology](#technology)
- [Permissions](#permissions)
- [Supported formats](#supported-formats)
- [Security and privacy](#security-and-privacy)
- [Sleep, screen lock and the lid](#sleep-screen-lock-and-the-lid)
- [Known limitations](#known-limitations)
- [Contributing](#contributing)
- [License](#license)

---

## How it was built

The application was developed with a coding agent as the orchestrator, backed by a fixed
set of tools. Each change was checked by compiling, by running the test suite and, where
only real hardware could tell, on a real television:

- **Orchestrator model**: DeepSeek V4.1 Flash.
- **Agents**: specialised subagents for reading the code base, implementing changes and
  verifying them independently, so the orchestrator never had to hold the whole
  repository in one context.
- **Gentle AI**: the harness that provides the workflow (Organic Driven Development),
  the task documents, the review lifecycle and the agent routing.
- **Engram**: persistent memory across sessions, so decisions, bugs and their causes
  survive a closed terminal.
- **GGA (Gentleman Guardian Angel)**: a review gate that runs on every commit attempt and
  blocks it when the change violates the rules in `AGENTS.md`.

## Requirements

- macOS 14 or later.
- Apple Silicon is the supported platform. The application is built as a universal binary,
  so it may run on Intel as well, but that was never tested.
- For building from source: Xcode 16 or later. The project was created and verified with
  Xcode 27.2 and Swift 6.4.2.
- No third-party dependencies, and no runtime to install.

## Installation

### From a release

1. Open the [releases page](https://github.com/zameo94/google-cast-player/releases) and
   download the `.dmg` of the version you want, together with its `.sha256` file.
2. Check the download, in the folder that holds both files:

   ```sh
   shasum -a 256 -c GoogleCastPlayer-1.0.0.dmg.sha256
   ```

   It must print `OK`. If it does not, the file is not the one that was published: delete
   it, download it again, and do not install it.
3. Open the image and drag **Google Cast Player** onto the **Applications** folder.
4. Launch it from Applications.

The application is signed ad-hoc, not notarized by Apple, so on the first launch macOS may
say it cannot verify it. To allow it, open **System Settings → Privacy & Security**,
scroll to the bottom and choose **Open Anyway**. This is a one-time step per version.

Do that only after the checksum in step 2 printed `OK`: the override lowers one of the
platform's protections, and the checksum is what shows the file is the published one.

One version is installed at a time. To go back to an older one, download its `.dmg` from
the releases page and install it the same way.

### From source

```sh
git clone https://github.com/zameo94/google-cast-player.git
open GoogleCastPlayer.xcodeproj   # choose the GoogleCastPlayer scheme and press Run
```

Or build from the command line:

```sh
xcodebuild -project GoogleCastPlayer.xcodeproj -scheme GoogleCastPlayer \
  -configuration Debug -destination 'platform=macOS' build
```

## Tested devices

| Device | Status |
| --- | --- |
| Google TV with Chromecast built-in | Verified: discovery, session, playback, pause, seek, volume, mute, and the resume after the device stopped its receiver |
| Chromecast (older models) | Not tested |

One cast was left running for 1 h 31 min with the display off and the screen locked, on
battery, and it kept playing. Closing the lid and the recovery that follows it were not
exercised deliberately on hardware; that path is covered by the test suite.

The application talks to the **Default Media Receiver** (`CC1AD845`), the receiver every
Cast device runs without a custom app, so any receiver that supports it should work.

## How it works

1. You choose a video file, or drop it on the window. The app reads its metadata with
   AVFoundation and judges whether the container and codecs match the target profile.
2. It finds the Cast devices on the local network through Bonjour (`_googlecast._tcp`).
3. When you press Play, it starts an HTTP server inside the app that serves **only that
   file**, under an unguessable path, with byte-range support so the device can seek.
4. It hands the URL to the device over Cast V2 and the device fetches the video directly
   from the Mac.
5. Playback controls and the volume reflect what the device reports, not what the app
   hopes happened.

## Technology

- Swift 6 and SwiftUI, with no third-party dependency.
- AVFoundation for metadata, `Network.framework` for the HTTP server, the Cast TLS
  connection and Bonjour discovery.
- The Cast V2 protocol is implemented by hand: a minimal protobuf codec, the connection,
  heartbeat, receiver and media namespaces, and the media commands.
- Tests use the Swift Testing framework and cover the protocol, the server, the state
  models and the orchestration.

## Permissions

- **Local network**: needed to find devices and to let a device fetch the file. macOS asks
  the first time the app searches; if the permission is denied the app says so instead of
  showing an empty list. It can be re-enabled in System Settings → Privacy & Security →
  Local Network.
- No camera, microphone, contacts or photo access is requested. The app reads only the
  file you select, and it does so while it is selected.

## Supported formats

- Target profile: MP4 container with H.264 video and AAC audio.
- MOV is reported as "may not be compatible", because MP4 is the prioritized container.
- Other containers (MKV, AVI, WebM) and codecs (HEVC on older receivers, VP9, ALAC) are
  reported as unsupported or device-dependent.
- There is no transcoding: a file the receiver cannot decode is reported as such, never
  converted.

## Security and privacy

- Files never leave the local network and are never uploaded. There is no account, no
  cloud component and no analytics.
- The HTTP server runs only while a cast is active, serves only the selected file and
  exposes it under an unguessable per-session path. Every other path answers 404, so the
  file system is not reachable. Requests are size-capped, malformed requests are
  rejected, and the server stops when the cast ends.
- The server speaks plain HTTP with no authentication beyond the path: it is meant for a
  trusted local network. Do not cast on a network you do not trust.
- The TLS connection to the device accepts the device's self-signed certificate, which is
  what Cast devices present. Trust comes from the local network, not from a certificate
  chain.

## Sleep, screen lock and the lid

While a cast is running the application holds a macOS activity assertion: the Mac stays
out of App Nap, which would otherwise throttle timers and network I/O once the window is
inactive, and out of idle sleep. Locking the screen, letting the display turn off or
leaving the window in the background does not end the cast.

Closing the lid is different: macOS always puts the Mac to sleep on lid close and no
application can override that, so the device stops. When the Mac wakes, the app reconnects
and resumes three seconds before the point where the device stopped.

A session that drops while the Mac is awake is handled the same way, with three attempts,
and the wake lock is released only when recovery gives up, so a short network loss cannot
put the Mac to sleep before the recovery had a chance to run.

The lock and display-sleep behaviour was verified over the 1 h 31 min cast described
above. The wake and recovery paths are covered by the test suite; the automatic recovery
has run once in real use after an unexpected session loss, but neither path was driven
deliberately on hardware.

If you want the Mac to stay awake with the lid closed, it is a system-level decision, both
options outside the application:

- **Clamshell mode**: connect a charger and an external display; macOS then keeps running
  with the lid closed.
- **A system-wide sleep override**, which applies to every application and costs battery
  life and heat:

  ```sh
  sudo pmset -a disablesleep 1    # revert with: sudo pmset -a disablesleep 0
  ```

While a cast runs, `pmset -g assertions` shows the assertion the app holds. Every step of
the cast lifecycle is written to the unified log:

```sh
log show --last 2h --info --predicate 'subsystem == "io.github.zameo94.GoogleCastPlayer"'
```

`--info` is needed because those messages are informational; without it only errors and
faults appear. The same entries can be followed live in Console.app by filtering on the
subsystem.

## Known limitations

- No transcoding: MKV, AVI and MOV files are not castable, and HEVC depends on the
  receiver model.
- The compatibility verdict describes the container and codecs of the file; it does not
  promise playback on a specific device.
- The displayed playback position is interpolated between status updates and can drift by
  about a second.
- While the Mac is asleep, for example with the lid closed, the cast stops. It resumes
  after the wake, but the video does not keep playing through the sleep.
- A device that stops its own receiver on purpose is not resumed automatically: the
  playback section offers Resume and Stop instead.
- If device discovery reports a device as removed right after a wake, the selection is
  cleared and the interrupted cast goes with it.

## Contributing

- `main` is stable and release ready; `dev` is the integration branch; features live on
  `feature/<name>` branches.
- Integrating into `dev`, promoting `dev` to `main`, pushing, opening pull requests and
  releasing all require the maintainer's explicit approval.
- Commits follow Conventional Commits.
- The optional pre-commit review gate runs GGA against `AGENTS.md`:

  ```sh
  cp .gga.example .gga   # set PROVIDER for your machine
  scripts/install-git-hooks.sh
  ```

  A failing review blocks the commit; the hook never skips the review silently.
- `scripts/make-dmg.sh` builds the Release app and packages it into
  `dist/GoogleCastPlayer-<version>.dmg`, which is what gets attached to a release. It is a
  maintainer tool: the disk image is not committed, so the repository stays free of
  binaries.

## License

Apache License 2.0. See [LICENSE](LICENSE).
