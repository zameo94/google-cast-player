Google Cast Player — Development

1. Current State
Overall status: Phase 0 to Phase 7 on main and verified on a physical device; the Phase 8 release candidate is integrated into dev, with the release decision pending.
Current development phase: Phase 8 — Stabilization and MVP Release (release candidate 1.0.0 integrated into dev; release approval pending).
Current milestone: The release decision: signing, notarization and version tagging.
Current feature branches: feature/release-stabilization (Phase 8), created from main at be69da3 and merged into dev; feature/sleep-and-reconnect (Phase 8), created from main at 565f112 and not yet integrated.
Current working branch: feature/sleep-and-reconnect; dev is used only to integrate completed feature branches.
Last verified commit: main is 565f112; feature commits are listed in section 7.
Last verified build: Debug build succeeded with xcodebuild on 2026-11-25 (see section 6).
Last verified test run: 173 unit tests passed with xcodebuild on 2026-11-26 (see section 6).
Last quality gate run: gga v2.10.1 on the staged files of each commit listed in section 7.
Last remote synchronization: main matches origin/main at 565f112. dev is ahead of origin/dev with the release candidate; the sleep-and-reconnect branch is local only; nothing has been pushed.

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
* The window shows the state on the device card itself: a selected card is blue and offers Connect, a spinner appears on it while connecting, and a connected card turns green and offers Disconnect; Cancel and the failure message with retry and dismiss live in the session row, and connecting again to the already connected device does nothing.
* 21 additional unit tests (125 in total) covering message encoding and framing, the client handshake against a scripted transport, heartbeat behaviour, load payloads, timeouts, transport loss and the connection state machine.

Phase 6 — end-to-end local video streaming:

* `PlaybackModel` owns one cast: it starts the local server for the selected file, builds the media request from its MIME type, hands the URL to the connected device, and stops serving when the cast ends or fails.
* `MediaServing` and `CastMediaLoading` keep the orchestration testable without a socket or a device; `LocalMediaServer` and `CastConnectionModel` provide the real implementations.
* The window offers "Play on <device>" once a device is connected and a video is selected, shows a spinner while starting, prints the served URL once the device accepted it, and offers Stop.
* Stop and Disconnect are separate actions: Stop ends the media and keeps the session, so the receiver stays reachable for another cast, while Disconnect also stops the receiver application and closes the connection.
* Ending a session sends a media STOP, a receiver STOP and a connection CLOSE before dropping the socket, then stops the server; closing the socket alone left the receiver playing and kept its cast screen alive. The stop commands carry a request id, which the receiver requires and silently ignores otherwise, and the receiver STOP falls back to stopping the current app when no session id was reported.
* Leaving the connected state stops the server, so the file stops being reachable exactly when the cast ends.
* Server failures and load failures now carry user-facing descriptions.
* 12 additional unit tests (137 in total), including an integration test that fetches the exact URL handed to the device, tests of the stop sequence, of stopping playback alone, of the cast orchestration and of a repeated connect.

Phase 7 — playback controls and reported state:

* `CastClient` reads `MEDIA_STATUS` into state, position, duration and idle reason, keeps the last known duration when an update omits the media block, and sends `PLAY`, `PAUSE` and `SEEK` with request ids.
* `CastConnectionModel` exposes an app-level `PlaybackSnapshot` and forwards the controls; the window depends only on that snapshot and never on Cast protocol types.
* `PlaybackControls` shows what the device reports: Playing on the device, Paused, Buffering, Finished or Playback failed, with a play or pause button enabled only when the media can accept it, a seek bar with elapsed and total time, and Stop.
* The elapsed time advances locally between status updates while the device reports playing, and realigns to every status it receives.
* The launch timeout is driven by an injectable sleeper, so timeout behaviour is tested without waiting on wall time.
* 9 additional unit tests (146 in total) covering status parsing, command payloads, snapshot mapping, status merging and the timeout path.

Phase 8 — stabilization and release candidate:

* The client reports when the device stops its receiver, and the window turns that into a clear "connect again" failure instead of showing a session that no longer exists.
* Loading, connecting, searching and casting indicators carry accessibility labels, and the device section offers an explicit "Search for devices again" action.
* The marketing version for the release candidate is 1.0.0.
* Release configuration builds successfully; automated tests run in Debug, because they use `@testable` and testability is intentionally off in Release.
* The README now documents installation, permissions, supported formats, security and privacy, and known limitations.
* Security review, as far as this environment allows: the server serves one file behind an unguessable path, answers 404 elsewhere, caps request size, rejects malformed requests, stops with the cast, and never leaves the LAN; the device certificate is accepted because Cast devices are self-signed; the HTTP traffic itself is plain, which is documented as a trusted-LAN assumption.
* 2 additional unit tests (148 in total) covering the receiver-stopped path in the client and in the connection state.
* `CastPowerAssertion` holds one `ProcessInfo` activity with `userInitiated` and `idleSystemSleepDisabled` for the whole duration of a cast: the process stays out of App Nap and the Mac stays out of idle sleep, so locking the screen or letting the display turn off no longer kills the media server and the device connection.
* The heartbeat now notices a session that stopped answering: a send failure or 45 seconds without any inbound message ends the connection, and `TLSCastTransport` closes a connection that fails after it was ready. A dead socket is reported instead of shown as connected.
* A lost connection during a cast becomes a new `interrupted` playback state that keeps the file and the last reported position, with Resume and Stop in place of the controls.
* The application watches `NSWorkspace.didWakeNotification`; after a wake it reconnects the session, reloads the file at the last position, and retries while the network comes back.
* `CastClient.Media` carries the start position, so a resumed cast continues where the device stopped instead of starting over.
* Closing the lid still sleeps the Mac, which no application can prevent; README documents that, the clamshell and `pmset disablesleep` options, and how to check the assertion with `pmset -g assertions`.
* A lost session no longer puts the Mac to sleep before recovery can run: the assertion stays held through the recovery attempts, which now also start without waiting for a wake. Giving up releases it.
* The cast lifecycle is written to the unified log (play, cast started and failed, interrupt with its reason, resume position, recovery outcome, connection lost, receiver stopped, silent device, media server listening and refusals), so a session that ends hours later can be explained with `log show`.
* The media server accepts up to 16 simultaneous connections and logs a refusal, so a temporary backlog cannot silently starve the receiver.
* Verification of the block above: `pmset -g log` shows the cast assertion held for 1h31m09s with the display off and on battery on 2026-11-25, so the idle-sleep and App Nap protection is observed behaviour rather than a unit test only. The wake recovery, the loss recovery and the diagnostics are covered by unit tests; the real cast that ended after those 1h31 took the app down with it (the app released the assertion, the Mac slept 5 seconds later) and the cause is not recorded, because the app wrote nothing to the unified log at the time.
* 25 additional unit tests (173 in total) covering the power assertion lifetime, the interrupted cast, the resume path, the wake and loss recovery attempts, the assertion kept during recovery, the lost-connection reporting, the reconnect and the position carried into a resumed load.

4. In Progress
* The release decision is open: no tag, no signing identity and no notarization have been chosen, so 1.0.0 is a built candidate rather than a published release.
* Release candidate 1.0.0 is built from source and ad-hoc signed; signing, notarization and distribution need the maintainer's decision.
* Stop keeps the session open by design, so the receiver and the cast indicator stay; Disconnect stops the receiver and closes the session, and the user confirmed both behaviours on hardware.
* Release approval has not been given; nothing has been tagged, notarized or published.

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
* Test run succeeded: 148 tests in 16 suites on 2026-11-25, and 173 tests in 17 suites on 2026-11-26. The Release configuration builds; tests run in Debug because they use `@testable`.
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
10. Start a cast, then lock the screen and let the display turn off; the video must keep playing. `pmset -g assertions` must list a `PreventUserIdleSystemSleep` assertion owned by GoogleCastPlayer while the cast runs.
11. With a cast running, close the lid, wait, then open it; the application must reconnect and resume the video where it stopped. A device that does not answer must leave the interrupted state with Resume and Stop instead of a session that only looks connected.

Status of these checks: on 2026-11-25 the user exercised the import flow, the metadata display and the verdict (items 1, 2, 3, 4 and 6) and, on a Google TV, local network access, the device list, the selection, the session, casting a compatible MP4, the playback controls (play, pause, seek and the duration bar) and the Stop and Disconnect actions (items 7 and 8, plus the cast flow). Item 5 (unreadable container), item 9 (device turned off while connected) and items 10 and 11 (screen lock and lid close, added with the wake work) were not exercised. Items 10 and 11 need the maintainer's machine: the power behaviour cannot be observed from the test host.

Note: the verdict describes the container and codecs only. Actual playback on a receiver is not verified and is not promised by the label.

Continuous integration: .github/workflows/ci.yml builds and tests the project on a macOS runner for pull requests and for pushes to main and dev. The workflow file parses as valid YAML, but it has not been executed on GitHub because no branch has been pushed.

7. Recent Work Log
The log is chronological: each row records what happened on that date, not the current state, which section 1 reports.

| Date | Branch | Work | Verification at that date | Commit |
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
| 2026-11-25 | feature/end-to-end-streaming | Stop the media and the receiver before closing the session | 134 tests passed; found because disconnecting left the receiver playing on hardware | d35e6d3 |
| 2026-11-25 | feature/end-to-end-streaming | Stop commands now carry request ids, and the stop runs before the server is stopped | 134 tests passed; the missing request id explains the stop being ignored on hardware | ab1cac5 |
| 2026-11-25 | feature/end-to-end-streaming | Stop the media only, leaving the session open, and keep Disconnect for ending it | 136 tests passed | 50ebf78 |
| 2026-11-25 | feature/end-to-end-streaming | Connect from the device card, with blue for selection and green for connection | 136 tests passed | 2e272b5 |
| 2026-11-25 | feature/end-to-end-streaming | Disconnect replaces Connect on a connected card, and a repeated connect keeps the session | 137 tests passed | 9f2c275 |
| 2026-11-25 | feature/end-to-end-streaming | A single disconnect action on the card | 137 tests passed | ba87133 |
| 2026-11-25 | dev | Integrated the Phase 6 branch | Build and tests re-run on dev after the merge | see section 6 |
| 2026-11-25 | main | Pull request #7 merged dev into main | Build and tests verified on dev before the merge | 021984c |
| 2026-11-25 | feature/playback-controls | Media status parsing, playback commands and the transport controls | 146 tests passed; gga required app-level playback types and deterministic timeout tests | c721470 |
| 2026-11-25 | dev | Integrated the Phase 7 branch | Build and tests re-run on dev after the merge | see section 6 |
| 2026-11-25 | main | Pull request #8 merged dev into main | Build and tests verified on dev before the merge | be69da3 |
| 2026-11-25 | feature/release-stabilization | Receiver-stop handling, accessibility labels, release documentation and version 1.0.0 | 148 tests passed in Debug, Release build succeeded | e8e3688 |
| 2026-11-25 | dev | Integrated the release candidate; the user confirmed the full cast flow and the playback controls on a Google TV | Build and tests re-run on dev after the merge | 711c06e |
| 2026-11-25 | dev | Integrated the Phase 3 branch | Build and tests re-run on dev after the merge | see section 6 |
| 2026-11-25 | feature/sleep-and-reconnect | Lost connections are reported, the session keeps the position and a reconnect opens a new session | 170 tests passed in Debug; gga rejected a polling test helper and a swallowed send error, both fixed | e3dfabb |
| 2026-11-25 | feature/sleep-and-reconnect | Cast power assertion, interrupted cast state, wake watcher and automatic resume at the last position | 170 tests passed in Debug, Release build succeeded; gga passed | d087878 |
| 2026-11-25 | feature/sleep-and-reconnect | Transport stores its connection before `connect()` returns | 170 tests passed in Debug; gga passed | 88fcdc6 |
| 2026-11-26 | feature/sleep-and-reconnect | Unified-log diagnostics, the wake lock kept through recovery and recovery that starts without a wake | 173 tests passed in Debug, Release build succeeded; found after a real 1h31 cast ended and the Mac slept in 5 seconds | c335b94 |

8. Blockers and Risks
No active blocker.

Risks and pending verification:

* Phase 0 to Phase 7 reached main through pull requests #2 to #8 and were verified on a Google TV. Phase 8 is integrated into dev and only the release decision remains.
* Discovery, connection and playback were confirmed on a Google TV on 2026-11-25. Other device models, and how quickly a device returns to its ambient screen after Stop, remain unverified.
* The test host of the automated suite cannot browse the network, because macOS grants local network access to an app only after the user allows it. Discovery therefore has no automated network test.
* Continuous integration has not run on GitHub yet; it can only be verified after the first push.
* The Cast client accepts the device's self-signed certificate, as Cast requires; the session is therefore trusted because it is on the local network, not because of a certificate chain.
* Casting again without stopping first stops the previous server, so an older session loses its media source; the window offers Stop for that, and broadcasting a replacement session belongs to the playback work.
* The media server speaks plain HTTP with no authentication beyond the unguessable per-session path. It is meant for a trusted local network and only while a session needs it; the server is not exposed outside the LAN by the app.
* The server runs only while a cast is active: `PlaybackModel` starts it for the selected file and stops it when the cast ends, and its behaviour is covered by tests.
* The interactive checklist was exercised by the user on a Google TV; items 5 (unreadable container), 9 (device turned off while connected), 10 (screen lock and display sleep) and 11 (lid close and wake recovery) were not exercised.
* The cast power assertion and the wake recovery are covered by unit tests only. Whether macOS honours the assertion on this Mac, and how the device behaves while the Mac sleeps, can only be verified with items 10 and 11 of section 6 on the maintainer's machine.
* The position shown between status updates is interpolated locally, so it can drift by a second until the next status arrives; seeking is sent only when the slider is released.
* The compatibility verdict describes the container and codecs only. Real playback on a receiver is unverified, so the interface never labels a file as playable, only as matching or not matching the format profile.
* Interactive and visual checks are manual: the shell has neither screen recording nor accessibility permission, and there is no UI test target. Section 6 records which checks the user exercised and which are still pending.
* Repository branch protection and required status checks cannot be configured from this environment and must be verified on GitHub by the user.
* The review gate depends on the locally configured AI provider. A review that misjudges valid code blocks the commit until it is rerun; build and test results remain the authoritative verification.

9. Next Objective
Decide the release:
1. Push dev and verify that the GitHub Actions workflow runs successfully on it, and configure branch protection (both require explicit user approval).
2. Authorize the promotion of dev to main and choose the distribution path: signing identity, notarization, and whether the 1.0.0 tag is created. Nothing is tagged or published without that approval.
3. Once released, keep the remaining manual items (unreadable container, device turned off while connected) in the checklist for the next pass.

Do not start release work before its planned phase.

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
