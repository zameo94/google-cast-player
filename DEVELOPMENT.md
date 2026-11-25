Google Cast Player — Development

1. Current State
Overall status: Phase 0, Phase 1 and Phase 2 verified and integrated into dev; promotion to main is pending.
Current development phase: Phase 2 — Media Access, Metadata and Compatibility (acceptance criteria verified; integrated into dev, not yet promoted to main).
Current milestone: Promotion of dev to main and Phase 3 preparation.
Current feature branches: feature/media-metadata-compatibility (Phase 2), created from main at 5877d89 and merged into dev.
Current working branch: dev, used only to integrate completed feature branches; feature work happens on feature/<name> branches.
Last verified commit: main is 5877d89; feature commits are listed in section 7.
Last verified build: Debug build succeeded with xcodebuild on 2026-11-25 (see section 6).
Last verified test run: 50 unit tests passed with xcodebuild on 2026-11-25 (see section 6).
Last quality gate run: gga v2.10.1 on the staged files of each commit listed in section 7.
Last remote synchronization: main matches origin/main at 5877d89. dev is ahead of origin/dev with the integrated Phase 2 work; nothing has been pushed.

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

4. In Progress
* Promotion of dev to main: Phase 2 is integrated and requires explicit user approval to reach main.
* Phase 3 (Cast device discovery) has not started and waits for the Phase 2 integration.

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
* Test run succeeded: 50 tests in 6 suites.
* The built application launches, keeps running and quits cleanly.
* An offscreen render of the screen confirmed the layout of the empty, loading, compatible, unsupported and metadata-error states. Visual appearance and interactive drag-and-drop were not inspected automatically: macOS denied screen recording and accessibility access to the shell, so they remain manual checks.

Manual checks (require a graphical session and cannot be automated on this machine):

1. Launch the application and confirm the empty state appears in the main window.
2. Drag an MP4 file onto the drop area; the card must show its name, "MP4", its size, duration, resolution, codecs and the format verdict.
3. Use "Choose Different Video…" (or Command-O) to replace the selection.
4. Drop a non-video file, for example a `.txt`; the error banner must explain the problem and the previous selection must stay.
5. Drop a file the container cannot open while it is being described; the card must show the metadata error instead of invented values.
6. Click "Remove" to return to the empty state.

Note: the verdict describes the container and codecs only. Actual playback on a receiver is not verified and is not promised by the label.

Continuous integration: .github/workflows/ci.yml builds and tests the project on a macOS runner for pull requests and for pushes to main and dev. The workflow file parses as valid YAML, but it has not been executed on GitHub because no branch has been pushed.

7. Recent Work Log
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

8. Blockers and Risks
No active blocker.

Risks and pending verification:

* Phase 0 and Phase 1 reached main through pull request #2. Phase 2 is integrated into dev and needs promotion to main before ROADMAP.md allows it to be marked complete.
* Continuous integration has not run on GitHub yet; it can only be verified after the first push.
* Chromecast discovery, connectivity and playback have never been exercised; the corresponding phases are not started.
* The compatibility verdict describes the container and codecs only. Real playback on a receiver is unverified, so the interface never labels a file as playable, only as matching or not matching the format profile.
* Visual appearance and interactive drag-and-drop in the running application are manual checks: the shell has neither screen recording nor accessibility permission, and no UI test target exists yet.
* Repository branch protection and required status checks cannot be configured from this environment and must be verified on GitHub by the user.
* The review gate depends on the locally configured AI provider. A review that misjudges valid code blocks the commit until it is rerun; build and test results remain the authoritative verification.

9. Next Objective
Promote Phase 2 and prepare Phase 3:
1. Push dev and verify that the GitHub Actions workflow runs successfully on it (pushing requires explicit user approval).
2. Authorize the promotion of dev to main so Phase 2 can be marked complete.
3. Only then start Phase 3 — Cast device discovery — following ROADMAP.md.

Do not start device discovery, media serving, Cast communication or playback before their planned phases.

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
