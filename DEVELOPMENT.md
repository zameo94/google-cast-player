Google Cast Player — Development

1. Current State
Overall status: Phase 0 to Phase 5 on main, with physical-device verification still pending; Phase 6 implemented on its feature branch.
Current development phase: Phase 6 — End-to-End Local Video Streaming (implemented; serving and handoff verified by tests, playback on a physical device pending).
Current milestone: Real-device verification of the full cast flow, then integration.
Current feature branches: feature/end-to-end-streaming (Phase 6), created from main at 51cdca4.
Current working branch: feature/end-to-end-streaming.
Last verified commit: main is 51cdca4; feature commits are listed in section 7.
Last verified build: Debug build succeeded with xcodebuild on 2026-11-25 (see section 6).
Last verified test run: 133 unit tests passed with xcodebuild on 2026-11-25 (see section 6).
Last quality gate run: gga v2.10.1 on the staged files of each commit listed in section 7.
Last remote synchronization: main matches origin/main at 51cdca4. The Phase 6 branch has not been pushed.

2. Verified Environment
Verified on the development machine before this status was written:

* macOS 26.6.2 on Apple Silicon (arm64).
* Xcode 27.2 (build 27B52), macOS 27.2 SDK.
* Swift 6.4.2.
* Git repository with remotes origin/main and origin/dev.
* gga v2.10.1 installed, backed by the OpenCode CLI 2.4.1.
* Local pre-commit hook invoking the review gate.

3. Completed Work
Only verified work is recorded here.

Phase 0 — repository and development foundation:

* Repository created under the MIT license.
* Project instructions (AGENTS.md), product roadmap (ROADMAP.md) and this status document published.
* dev branch created and integrated with main.
* .gitignore excludes local AI tooling (.atl/, .gga) and macOS, Xcode, test and SwiftPM build artifacts (delivered by feature/repository-foundation).
* GGA review gate is reproducible: the repository ships .opencode/agents/gga-reviewer.md, .gga.example, scripts/hooks/pre-commit and scripts/install-git-hooks.sh.
* The review gate was verified end to end in an isolated throw-away repository: it blocks a commit with a real violation and passes clean files.
* The hook installer was verified for install and uninstall paths.

Phase 1 — native macOS application foundation and media import:

* Xcode project with an application target and a hosted unit test target, plus a shared scheme.
* Swift 6 SwiftUI application entry point with a single main window.
* Media file model (`MediaFile`, `MediaFormat`) independent of SwiftUI and media frameworks.
* Import validation (`MediaImporter`) for missing files, folders, non-file URLs, non-movie types and unreadable files, with user-facing messages.
* Import state (`MediaImportModel`) covering selection, replacement, removal, error reporting and picker cancellation.
* Main window with empty state, native file picker, drag and drop, selected-file presentation (name, container format, size), replacement and removal, and an error banner.
* 18 automated unit tests across the media format, importer and import state.
* Verified Debug build, clean compiler warnings and passing test run (see section 6).
* Repository documentation (README.md) and a GitHub Actions workflow for build and tests.

Phase 2 — media access, metadata and compatibility:

* `MediaMetadata`, `VideoCodec` and `AudioCodec` describe duration, resolution and codecs as plain values, independent of SwiftUI.
* `MediaMetadataExtractor` reads what the container reports through AVFoundation, without decoding or preparing playback; unreadable files produce an error instead of invented data.
* `MediaCompatibilityEvaluator` is a pure function over metadata and format: it accepts MP4/M4V with H.264 and AAC, reports MOV and undeterminable properties as uncertain, and rejects other containers or codecs with an explanation.
* `SecurityScopedFileAccess` acquires and releases the security scope of the selected file; `MediaImportModel` holds access while a file is selected and releases it on replacement or removal.
* The main window shows duration, resolution, codecs, a format verdict with its reasons, a loading state and a metadata error state.
* 32 additional unit tests (50 in total) covering codec mapping, the compatibility rules, extraction from real H.264 and AAC fixtures, access lifetime and metadata states, including a selection replaced while metadata is loading.
* Verified Debug build, clean compiler warnings and passing test run (see section 6).

Phase 3 — Cast device discovery:

* `CastDevice` describes a discovered device and is identified by its Bonjour service name, which is the only value the network always reports.
* `DiscoveredDeviceSet` turns browse snapshots into appeared, changed and vanished events, collapsing the duplicate reports macOS delivers per interface.
* `BonjourCastDeviceBrowser` browses `_googlecast._tcp` through Network.framework, never connects, and reports a blocked local network permission with an actionable message instead of an empty list.
* `DeviceDiscoveryModel` owns the discovered devices, the visible search state and the user's selection; a device that disappears clears its own selection.
* `MainScreen` presents the search state, the device list with selection, an empty result with "Search Again", and a failure with its message.
* The app declares `NSBonjourServices` and `NSLocalNetworkUsageDescription`, so macOS can ask for local network access.
* 23 additional unit tests (73 in total) covering device parsing, duplicate reports, appear/update/disappear events, selection lifetime and failure states.

Phase 4 — local HTTP media server:

* `LocalMediaServer` serves exactly one file over HTTP through Network.framework, on an ephemeral port, and stops on request.
* The served path carries an unguessable per-start token; every other path answers 404, so the file system is never reachable and no second resource can be read.
* GET and HEAD are supported; other methods answer 405 with the allowed methods.
* Byte ranges answer 206 with `Content-Range`; an unsatisfiable range answers 416 with `bytes */size`; a range that cannot be understood is ignored and the whole file is served.
* Responses carry the file MIME type derived from its extension, the exact content length, and `Accept-Ranges: bytes`.
* Malformed request heads answer 400, oversized heads answer 413, and each connection carries one response and is then closed.
* `LocalNetworkAddress` resolves the Mac's primary IPv4 address so the returned URL is reachable from the network.
* 31 additional unit tests (104 in total), including loopback integration tests for full, ranged, HEAD, 404, 405, 400 and 416 responses, plus lifecycle checks.

Phase 5 — Cast communication:

* `CastMessage` encodes and decodes Cast V2 protobuf messages by hand, with length-prefixed framing, so the project still has no third-party dependency.
* `TLSCastTransport` connects to the device endpoint over TLS and accepts the device's self-signed certificate, which is what Cast devices present.
* `CastClient` runs the protocol the app needs: the connection namespace, heartbeat replies and its own pings, launching the Default Media Receiver, and sending a load command with the media URL, content type and stream type.
* `CastDevice` now carries the Bonjour endpoint discovery reported, so a session can be opened without resolving the service again.
* `CastConnectionModel` exposes real session states: idle, connecting, connected and failed with the reason the device or transport reported.
* The window shows the state: a Connect button, a spinner with Cancel while connecting, a green Connected label and card with Disconnect, and a red failure with the message, a retry and a dismiss action.
* 21 additional unit tests (125 in total) covering message encoding and framing, the client handshake against a scripted transport, heartbeat behaviour, load payloads, timeouts, transport loss and the connection state machine.

Phase 6 — end-to-end local video streaming:

* `PlaybackModel` owns one cast: it starts the local server for the selected file, builds the media request from its MIME type, hands the URL to the connected device, and stops serving when the cast ends or fails.
* `MediaServing` and `CastMediaLoading` keep the orchestration testable without a socket or a device; `LocalMediaServer` and `CastConnectionModel` provide the real implementations.
* The window offers "Play on <device>" once a device is connected and a video is selected, shows a spinner while starting, prints the served URL once the device accepted it, and offers Stop, which stops the server and closes the session.
* Leaving the connected state stops the server, so the file stops being reachable exactly when the cast ends.
* Server failures and load failures now carry user-facing descriptions.
* 8 additional unit tests (133 in total), including an integration test that fetches the exact URL handed to the device and compares the bytes.

4. In Progress
* Playback of a real file on a physical device: the full flow has not run on hardware yet, so the Phase 6 acceptance criterion is open.
* Phase 7 (playback controls and reported state) has not started and waits for the hardware verification.

5. Quality Gate and Tooling Decisions
* The review gate is enforced by a Git pre-commit hook installed with scripts/install-git-hooks.sh; the hook refuses to run when gga or the local .gga configuration is missing instead of skipping the review.
* .gga stays untracked because the AI provider is a per-machine choice; .gga.example documents the required settings.
* The review uses the project-scoped reviewer agent `.opencode/agents/gga-reviewer.md` through `OPENCODE_AGENT="gga-reviewer"`. The agent must answer with a single `STATUS:` verdict, which is what strict mode parses.
* Reason for the dedicated agent: the previous configuration invoked the general-purpose default agent, whose free-form answers sometimes placed the verdict outside the parsed window, blocking valid commits. A reviewer scoped to the verdict contract and without tools removes that source of variability.

6. Build and Test Procedures
The project is GoogleCastPlayer.xcodeproj with the shared scheme GoogleCastPlayer, the GoogleCastPlayer application target and the GoogleCastPlayerTests unit test target.

Build:

    xcodebuild -project GoogleCastPlayer.xcodeproj -scheme GoogleCastPlayer \
      -configuration Debug -destination 'platform=macOS' build

Test:

    xcodebuild -project GoogleCastPlayer.xcodeproj -scheme GoogleCastPlayer \
      -configuration Debug -destination 'platform=macOS' test

Verified on 2026-11-25 with Xcode 27.2:

* Clean Debug build succeeded with no compiler warnings.
* Test run succeeded: 133 tests in 16 suites.
* The built application launches, keeps running and quits cleanly.
* An offscreen render confirmed the layout of the video states. The new screen hosts a scroll view, which the offscreen renderer cannot draw, so the device section is a manual check.
* Discovery was verified end to end against a Bonjour service registered on this machine: the browser reported the device once with its TXT record, and reported it removed when the service stopped. The test host itself cannot browse, because macOS gives it no local network access without a user decision.

Manual checks (require a graphical session and cannot be automated on this machine):

1. Launch the application and confirm the empty state appears in the main window.
2. Drag an MP4 file onto the drop area; the card must show its name, "MP4", its size, duration, resolution, codecs and the format verdict.
3. Use "Choose Different Video…" (or Command-O) to replace the selection.
4. Drop a non-video file, for example a `.txt`; the error banner must explain the problem and the previous selection must stay.
5. Drop a file the container cannot open while it is being described; the card must show the metadata error instead of invented values.
6. Click "Remove" to return to the empty state.
7. Allow local network access when macOS asks; the device section must list the Cast devices on the network.
8. Select a device; the selection must be visible and must survive other devices appearing.
9. Turn the selected device off or block its network; the device must disappear and its selection must be cleared.

Status of these checks: the user exercised the import flow, the metadata display and the verdict in the running app on 2026-11-25 (items 1, 2, 3, 4 and 6). Item 5 and the device checks 7 to 9 are pending; the device checks need a physical Cast device powered on and reachable.

Note: the verdict describes the container and codecs only. Actual playback on a receiver is not verified and is not promised by the label.

Continuous integration: .github/workflows/ci.yml builds and tests the project on a macOS runner for pull requests and for pushes to main and dev. The workflow file parses as valid YAML, but it has not been executed on GitHub because no branch has been pushed.

7. Recent Work Log
The log is chronological: each row records what happened on that date, not the current state, which section 1 reports.

| Date | Branch | Work | Verification | Commit |
| --- | --- | --- | --- | --- |
| 2026-11-24 | main | Initial repository setup and project instructions | Repository state inspected | d3a2b76 |
| 2026-11-24 | main | Product roadmap and development documentation | Documented | e8f9263, 59b6adf |
| 2026-11-25 | main | AGENTS.md revised | Documented | 0f14ad9 |
| 2026-11-25 | feature/repository-foundation | Expanded ignore rules for macOS and Xcode artifacts | Reviewed as a non-matching path, committed | 170a23f |
| 2026-11-25 | feature/repository-foundation | Reproducible GGA review gate and hook installer | gga reviewed the staged Markdown; gate verified in an isolated repository | e9cf748 |
| 2026-11-25 | feature/repository-foundation | Phase 0 status documented | Reviewed by gga | 7ce2af7 |
| 2026-11-25 | feature/repository-foundation | Review agent required to quote evidence for findings | Reviewed by gga | de2d70a |
| 2026-11-25 | feature/app-foundation-media-import | Xcode project, media model, importer, import state, SwiftUI screen and unit tests | Debug build succeeded; 18 tests passed; gga reviewed the staged Swift files | 2f8039b |
| 2026-11-25 | feature/app-foundation-media-import | README, CI workflow and this status update | Documented | 03fc185 |
| 2026-11-25 | feature/app-foundation-media-import | Manual verification checklist for the import flow | Documented | aa0a859 |
| 2026-11-25 | dev | Integrated both feature branches | Build and tests re-run on dev after the merge | see section 6 |
| 2026-11-25 | main | Pull request #2 merged dev into main | Build and tests verified on dev before the merge | 5877d89 |
| 2026-11-25 | feature/media-metadata-compatibility | Metadata extraction, codec mapping and compatibility rules with 30 new tests | 48 tests passed; gga reviewed the staged Swift files | ff89ebb |
| 2026-11-25 | feature/media-metadata-compatibility | Access lifetime, metadata states and presentation | 48 tests passed; gga rejected the first "Compatible" label as an unverified guarantee and passed the corrected one | b194f7f |
| 2026-11-25 | feature/media-metadata-compatibility | Fixed AAC detection: AVFoundation reports plain AAC as `aac`, not only `mp4a` | Regression tests failed on the old mapping and pass on the new one; real files reassessed | b25a0eb |
| 2026-11-25 | dev | Integrated the Phase 2 branch | Build and tests re-run on dev after the merge | see section 6 |
| 2026-11-25 | main | Pull request #3 merged dev into main | Build and tests verified on dev before the merge | 5255e19 |
| 2026-11-25 | feature/cast-device-discovery | Bonjour discovery, device identity and duplicate collapse | 73 tests passed; discovery verified against a registered Bonjour service | 7624a69 |
| 2026-11-25 | feature/cast-device-discovery | Device state, selection and the device section of the window | 73 tests passed; gga reviewed the staged Swift files | 05baa91 |
| 2026-11-25 | feature/cast-device-discovery | Device cards, card-wide selection and the honest "not connected yet" caption | 73 tests passed | 62958e5 |
| 2026-11-25 | main | Pull request #4 merged dev into main | Build and tests verified on dev before the merge | bcf28e3 |
| 2026-11-25 | feature/local-http-media-server | Local HTTP server with range support, access restriction and lifecycle | 104 tests passed; the file was fetched over the LAN address byte for byte | 0d0f1be |
| 2026-11-25 | dev | Integrated the Phase 4 branch | Build and tests re-run on dev after the merge | see section 6 |
| 2026-11-25 | main | Pull request #5 merged dev into main | Build and tests verified on dev before the merge | c31a80b |
| 2026-11-25 | feature/cast-communication | Cast V2 message codec, TLS transport and protocol client | 125 tests passed; gga rejected a polling helper and it was replaced by an event wait | 25d6c64 |
| 2026-11-25 | feature/cast-communication | Connection state and the connection UI | 125 tests passed | 0de3462 |
| 2026-11-25 | feature/cast-communication | Session controls: cancel, disconnect, dismiss | 125 tests passed | 25d1b2c |
| 2026-11-25 | dev | Integrated the Phase 5 branch | Build and tests re-run on dev after the merge | see section 6 |
| 2026-11-25 | main | Pull request #6 merged dev into main | Build and tests verified on dev before the merge | 51cdca4 |
| 2026-11-25 | feature/end-to-end-streaming | Cast orchestration, cast controls and the served URL in the window | 133 tests passed; gga rejected an unguarded URL literal in the tests and it was fixed | bafdfa4 |
| 2026-11-25 | dev | Integrated the Phase 3 branch | Build and tests re-run on dev after the merge | see section 6 |

8. Blockers and Risks
No active blocker.

Risks and pending verification:

* Phase 0 to Phase 5 reached main through pull requests #2 to #6. Phase 6 is implemented on its branch; both Phase 5 and Phase 6 still need a physical device to confirm the connection and playback.
* Discovery has not seen a physical Cast device yet: it was verified against a Bonjour service registered on this machine, which exercises the same browser path. The acceptance criterion about real devices needs a device powered on and reachable.
* The test host of the automated suite cannot browse the network, because macOS grants local network access to an app only after the user allows it. Discovery therefore has no automated network test.
* Continuous integration has not run on GitHub yet; it can only be verified after the first push.
* The Cast client accepts the device's self-signed certificate, as Cast requires; the session is therefore trusted because it is on the local network, not because of a certificate chain.
* Casting again without stopping first stops the previous server, so an older session loses its media source; the window offers Stop for that, and broadcasting a replacement session belongs to the playback work.
* The media server speaks plain HTTP with no authentication beyond the unguessable per-session path. It is meant for a trusted local network and only while a session needs it; the server is not exposed outside the LAN by the app.
* The server is not wired into the window yet: nothing starts it automatically, and Phase 6 owns that lifecycle. Its behavior is covered by tests instead.
* Chromecast discovery, connectivity and playback have never been exercised; the corresponding phases are not started.
* The compatibility verdict describes the container and codecs only. Real playback on a receiver is unverified, so the interface never labels a file as playable, only as matching or not matching the format profile.
* Interactive and visual checks are manual: the shell has neither screen recording nor accessibility permission, and there is no UI test target. Section 6 records which checks the user exercised and which are still pending.
* Repository branch protection and required status checks cannot be configured from this environment and must be verified on GitHub by the user.
* The review gate depends on the locally configured AI provider. A review that misjudges valid code blocks the commit until it is rerun; build and test results remain the authoritative verification.

9. Next Objective
Verify the cast flow on hardware, then integrate Phase 6:
1. Connect to a real device, cast a compatible MP4 and confirm the video plays from the Mac (manual check, needs the device on the network).
2. Record the outcome here, then integrate feature/end-to-end-streaming into dev and promote it with explicit user approval.
3. Only then start Phase 7 — playback controls and reported state — following ROADMAP.md.

Do not start media serving, Cast communication or playback before their planned phases.

10. Maintenance Rules
* Update this file after each meaningful development milestone.
* Record only verified results or clearly identified user-confirmed information.
* Keep the next objective specific and actionable.
* Record commit hashes and actual build and test results when available.
* Do not mark a phase complete until its acceptance criteria have been verified and its required integration into main has occurred.
* Preserve unresolved issues and blockers until they are actually resolved.
* Do not overwrite historical work log entries; append new entries.
* Keep product scope and acceptance criteria in ROADMAP.md, not duplicated here.
* Use AGENTS.md as the authoritative source for agent workflow and permissions.
