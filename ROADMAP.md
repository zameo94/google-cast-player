Google Cast Player — Product Roadmap
1. Product Vision
Google Cast Player is a native macOS application that allows users to play local video files on Chromecast and Google TV devices.
The application must stream files directly from the user's Mac to the selected Cast device over the local network.
The product must not require:
* Cloud services.
* External media servers.
* Uploading files to the Internet.
* Third-party streaming platforms.
* Video transcoding for the MVP.
The primary goal is a simple, reliable, native macOS experience.
2. Product Principles
* Native macOS application built with Swift and SwiftUI.
* Local-first architecture.
* Keep media files on the user's Mac.
* Stream directly over the local network.
* Use Google Cast for receiver communication and playback control.
* Use a local HTTP server to deliver media to the Cast receiver.
* Keep Cast protocol implementation isolated from the UI.
* Keep media delivery and Cast communication as separate architectural responsibilities.
* Prefer simple, maintainable architecture over unnecessary abstractions.
* Prioritize reliability, security, and meaningful automated tests.
* Do not introduce external dependencies without a clear technical reason.
* Do not silently expand the MVP scope.
3. MVP Scope
The MVP must allow a user to:
1. Import a local video file.
2. Inspect its basic information and compatibility.
3. Discover available Chromecast and Google TV devices on the local network.
4. Select a Cast device.
5. Establish a Cast session with the selected device.
6. Make the selected local video available through the Mac's integrated HTTP server.
7. Start streaming a compatible local video to the selected device.
8. Control basic playback.
9. Understand connection, playback, and file errors.
Initial media compatibility priority:
* MP4 container.
* H.264 video.
* AAC audio.
Unsupported media must be identified and reported clearly. Do not add transcoding to solve compatibility problems in the MVP.
3.1 Cast and HTTP Responsibilities
Cast and HTTP are complementary technologies. Neither replaces the other.
Google Cast communication
Responsible for:
* Discovering and connecting to Cast devices through the appropriate components.
* Establishing and managing Cast sessions.
* Launching or communicating with the receiver application.
* Sending media loading commands.
* Sending playback commands.
* Receiving playback status and device responses.
* Handling connection failures and disconnections.
Local HTTP media delivery
Responsible for:
* Making the selected local media available over the LAN.
* Providing the media URL to the Cast communication layer.
* Serving the requested media data to the receiver.
* Supporting HTTP Range requests and seeking.
* Restricting access to the authorized media resource.
* Managing the HTTP server lifecycle.
The expected playback flow is:
1. The user selects a local video.
2. The application starts its local HTTP server for that video.
3. The application establishes a Cast session with the selected device.
4. The application sends the local HTTP media URL through Cast communication.
5. The Cast receiver requests the video directly from the Mac.
6. The Mac serves the requested media data over the local network.
7. The application controls playback through the Cast session.
The Mac must remain the source of the media. The video must not be uploaded to a cloud service or external media server.
4. Development Roadmap
Each phase must have a clear implementation scope, meaningful tests, and verifiable acceptance criteria.
A phase is complete only when its acceptance criteria have been verified and its work has been integrated into main.
Work may be integrated into dev before promotion to main, according to the Git workflow defined in AGENTS.md.
Phase 0 — Repository and Development Foundation
Status: Verify existing implementation.
Objectives:
* Establish a reproducible development environment.
* Verify project instructions and Git workflow.
* Establish reliable repository hooks and automated quality checks.
* Establish build and test commands where an application project exists.
* Keep local configuration and personal machine data out of Git.
* Establish maintainable repository documentation.
* Establish the initial CI infrastructure where it can be meaningfully validated.
Acceptance criteria:
* The repository has a clear and reproducible development workflow.
* Local-only configuration is ignored.
* Repository instructions are consistent and do not contradict one another.
* Available build and test procedures are documented accurately.
* Automated quality checks can be executed and their results verified where applicable.
* Repository hooks work reliably where configured.
* No unverified build, test, or CI result is reported as successful.
Phase 1 — Native Application Foundation and Media Import
Status: Not assessed.
Objectives:
* Create the native macOS SwiftUI application structure.
* Implement the main application window.
* Implement video drag-and-drop.
* Implement the native file picker.
* Display selected file name, format, and size.
* Allow the user to remove the selected file.
* Handle invalid and inaccessible files.
* Create a suitable media information model.
Acceptance criteria:
* The application launches successfully.
* A user can import a local video using the file picker.
* A user can import a local video using drag-and-drop.
* The selected file's basic information is displayed correctly.
* Invalid or inaccessible files produce understandable errors.
* The selection can be removed and replaced.
* Meaningful automated tests cover the media information model and relevant behavior.
Phase 2 — Media Access, Metadata, and Compatibility
Status: Not assessed.
Objectives:
* Make local file access reliable.
* Implement security-scoped resource handling where required.
* Extract relevant media metadata.
* Identify container, video codec, audio codec, duration, and resolution when available.
* Detect compatibility with the initial MVP target.
* Explain unsupported or potentially incompatible media to the user.
Acceptance criteria:
* File access remains valid for the required lifetime.
* Security-scoped access is correctly acquired and released where applicable.
* Metadata extraction handles missing or incomplete information.
* Compatibility assessment is covered by automated tests.
* Unsupported formats are reported without crashing the application.
Phase 3 — Cast Device Discovery
Status: Not assessed.
Objectives:
* Discover Chromecast and Google TV devices on the local network.
* Evaluate Bonjour/mDNS and other technically justified discovery mechanisms.
* Present discovered devices in the application.
* Handle device appearance, disappearance, and network changes.
* Allow the user to select a target device.
* Handle local network permissions and discovery failures.
Acceptance criteria:
* Devices on the local network can be discovered.
* Discovery results are reflected in the UI.
* Unavailable devices are handled gracefully.
* Network and permission errors are understandable.
* Discovery logic is separated from the UI and covered by appropriate tests.
Phase 4 — Local HTTP Media Server
Status: Not assessed.
Objectives:
* Implement the integrated local HTTP server.
* Bind the server to an appropriate local network interface.
* Serve selected local media files securely.
* Support GET and HEAD requests.
* Support HTTP Range requests.
* Return correct partial-content responses (206).
* Return appropriate responses for invalid and unsatisfiable ranges.
* Set correct MIME types and response headers.
* Restrict access to the intended media resource.
* Manage server startup, shutdown, and resource cleanup.
* Ensure the server is available to the selected Cast device over the LAN.
Acceptance criteria:
* The server can serve a selected local media file over the LAN.
* GET and HEAD requests work correctly.
* Valid Range requests return correct 206 responses.
* Invalid and unsatisfiable ranges are handled correctly.
* Content types and content lengths are correct.
* Access is limited to the intended local media resource.
* Automated tests cover HTTP behavior and file access restrictions.
* The server can be stopped without leaving resources running.
* No public Internet exposure or cloud media transfer is required.
Phase 5 — Cast Communication
Status: Not assessed.
Objectives:
* Evaluate the available Google Cast SDK and protocol implementation options.
* Verify macOS compatibility, licensing, maintenance status, and technical constraints.
* Select a justified implementation approach.
* Implement the required Cast communication.
* Establish and manage a connection to a selected device.
* Handle receiver application launch and media session creation.
* Send media loading commands.
* Process device responses and connection events.
* Handle disconnects and protocol errors.
Architecture requirements:
* Keep Cast communication isolated from SwiftUI.
* Define clear interfaces between the Cast layer and application state.
* Avoid coupling the Cast implementation to the media server internals.
* Do not assume an official native macOS Cast Sender SDK exists.
* Do not introduce an external SDK or dependency without evaluating its suitability.
* Prefer a maintainable and testable implementation.
Acceptance criteria:
* A connection can be established with a compatible Cast device.
* The receiver application can be launched or addressed as required.
* Media load commands can be sent.
* Connection state and errors are communicated to the application.
* Protocol handling has appropriate tests.
* The implementation has been verified against a real compatible device.
Phase 6 — End-to-End Local Video Streaming
Status: Not assessed.
Objectives:
* Connect media selection, local HTTP serving, and Cast communication.
* Start the HTTP server for the selected file.
* Generate the correct local media URL.
* Send the local HTTP URL to the selected Cast device through Cast communication.
* Start playback of compatible local files.
* Handle loading, playback start, failure, and disconnect states.
* Ensure the local server remains available for the duration of playback.
* Coordinate Cast session and HTTP server lifecycle.
* Clean up resources when playback ends or the session disconnects.
Acceptance criteria:
* A compatible local MP4 video can be played on a real Chromecast or Google TV device.
* The media is served directly from the Mac over the local network.
* The Cast receiver retrieves the media from the Mac's HTTP server.
* No cloud upload or external media server is involved.
* Playback errors are handled gracefully.
* Server and Cast session resources are cleaned up correctly.
* The complete workflow has been verified on physical hardware.
Phase 7 — Playback Controls and User Experience
Status: Not assessed.
Objectives:
* Implement play and pause.
* Implement stop/disconnect.
* Display playback state.
* Display current position and duration when supported.
* Implement seeking when supported by the receiver.
* Improve device selection and connection feedback.
* Add loading, empty, error, and disconnected states.
* Refine the native macOS experience.
* Ensure the UI reflects actual Cast receiver state.
Acceptance criteria:
* Basic playback controls work with a real Cast device.
* The UI reflects actual receiver state.
* Seeking behaves correctly when supported.
* Disconnecting releases the relevant resources.
* Common user errors have clear explanations.
* Controls never present simulated functionality as a real Cast operation.
Phase 8 — Stabilization and MVP Release
Status: Not assessed.
Objectives:
* Perform end-to-end testing.
* Review security and local network exposure.
* Review error handling and resource management.
* Improve accessibility and usability.
* Review performance and reliability.
* Document installation, permissions, limitations, and supported formats.
* Prepare a release candidate.
Acceptance criteria:
* All MVP acceptance criteria are satisfied.
* Build and automated tests pass.
* Critical defects are resolved.
* Security review is completed.
* Documentation reflects actual application behavior.
* Real-device playback has been verified.
* Release is explicitly approved by the user.
5. Architecture Guidelines
Keep the application separated into clear responsibilities. The final structure must be based on actual implementation needs, not on creating folders without purpose.
Expected logical components:
* Application and UI.
* Application state and playback coordination.
* Media import and metadata.
* Local file access.
* Cast device discovery.
* Cast communication and session management.
* Local HTTP media server.
* Playback state and controls.
Architectural Boundaries
UI
* Displays application state.
* Sends user actions to appropriate application services.
* Does not implement networking protocols directly.
* Does not contain Cast protocol implementation details.
Media layer
* Handles selected media resources.
* Extracts metadata.
* Evaluates compatibility.
* Manages authorized file access.
Cast layer
* Handles device communication and session management.
* Sends receiver commands.
* Receives and translates device responses.
* Does not implement file serving.
HTTP layer
* Serves only authorized media resources.
* Handles HTTP requests and byte ranges.
* Does not implement Cast protocol commands.
* Does not expose arbitrary filesystem paths.
Playback coordination
* Coordinates media selection, server availability, Cast sessions, and playback state.
* Ensures resources are started and stopped in the correct order.
* Exposes application-friendly state to the UI.
The Cast layer must receive the media URL through a clear interface. It must not depend on the internal implementation of the HTTP server.
6. Development and Integration Rules
Follow the Git workflow defined in AGENTS.md:
* Create feature branches directly from the latest main.
* Integrate completed features into dev.
* Promote dev to main only through the approved integration workflow.
* Never push, merge, open PRs, or release without the user's explicit authorization.
Do not assume that work in dev is available to a feature branch created from main.
Identify dependencies between roadmap items before starting work. If a dependency has not been integrated into main, report it and propose the correct sequence.
Prefer small, reviewable implementation increments.
Do not mark a phase complete merely because its feature branch has been implemented or integrated into dev.
A phase is complete only after its acceptance criteria have been verified and the corresponding work has reached main.
7. Roadmap Maintenance
This document describes the intended product direction, development phases, and acceptance criteria.
The repository uses three complementary documents:
* AGENTS.md: permanent development instructions, working rules, quality requirements, and autonomy boundaries.
* ROADMAP.md: product vision, development phases, scope, dependencies, and acceptance criteria.
* DEVELOPMENT.md: current implementation status, completed and verified work, active tasks, blockers, and the next recommended action.
Do not create or maintain PROJECT_STATUS.md. Use DEVELOPMENT.md for operational project status.
When implementation details change:
* Update this roadmap only when the product scope, phase structure, or technical direction genuinely changes.
* Do not mark a phase complete merely because code has been written.
* Verify acceptance criteria before changing a phase status.
* Record important scope changes and their rationale.
* Keep DEVELOPMENT.md synchronized with the actual repository state.
* Never report unverified implementation, testing, hardware, or integration results as complete.
The roadmap must remain concise enough to be useful as an ongoing development reference.
