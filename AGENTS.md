Google Cast Player — Development Agent Instructions
1. Project Identity and Goal
The official project name is Google Cast Player.
Google Cast Player is an open-source native macOS application that allows users to play video files already stored on their Mac on Chromecast and Google TV devices.
The expected main workflow is:
1. The user selects or drags and drops a local video file.
2. The application discovers compatible Google Cast devices on the local network.
3. The user selects a device and starts casting.
4. The Mac makes the selected file available through an integrated local HTTP server.
5. The Cast device plays the video while the Mac controls the playback session.
The application must be simple, fast, lightweight, secure, and intuitive. It must not evolve into a general-purpose media center.
2. Language, Communication, and Working Method
* Communicate with the user in Italian unless explicitly requested otherwise.
* Use English for source code, identifiers, comments, technical documentation, Git commit messages, and Pull Request descriptions unless the project explicitly requires another language.
* Before modifying the project, inspect the actual repository and development environment.
* Work in small, verifiable, incremental tasks.
* Prefer focused, reviewable changes over large batches of unrelated modifications.
* Before making significant architectural decisions, explain the alternatives, advantages, limitations, and consequences to the user.
* Never assume that a feature exists merely because files, types, protocols, or buttons referring to it are present.
* Always distinguish between implemented features, prototypes, simulations, and outstanding work.
* Never fabricate build results, test results, device connections, CI results, or verification outcomes.
* If information or tools are missing, state this clearly.
* Ask the user only when an essential decision, permission, or clarification is genuinely required.
* Do not repeatedly ask for approval for ordinary development steps already covered by the approved task or mission.
* Keep the user informed about meaningful decisions, blockers, completed milestones, and changes in scope.
3. Platform and Technologies
Target platform: macOS on Apple Silicon.
Preferred technologies:
* Swift 6, compatible with the actual installed Xcode version and effective project settings.
* SwiftUI for the user interface.
* AVFoundation for media information and metadata extraction.
* Network.framework for the local HTTP server and networking features, where appropriate.
* Bonjour/mDNS for local network device discovery.
* Native Apple APIs whenever available and suitable.
Do not introduce external frameworks or dependencies without concrete technical justification.
Before adding a dependency, verify:
* Maintenance status.
* License compatibility.
* macOS and Swift compatibility.
* Security implications.
* Actual necessity.
* Long-term maintenance implications.
Do not assume that an official native macOS Google Cast Sender SDK is available. Verify the currently usable options before selecting a solution.
Evaluate the feasibility and technical requirements of implementing the Google Cast V2 protocol.
4. Product Scope
The application is specifically designed to play local video files from a Mac on Chromecast and Google TV devices.
Do not introduce the following features unless the user explicitly approves a change in product scope:
* A media server or general-purpose media center such as Plex or Jellyfin.
* IPTV.
* Internet video streaming or a general-purpose browser.
* Accounts, login systems, cloud backends, or cloud synchronization.
* Movie catalogs, posters, scraping, or advanced library management.
* Electron or web-based application architecture.
* Unnecessary third-party services.
* Features unrelated to the main local-video-to-Cast workflow.
The source of the video is the local file explicitly selected by the user.
5. Architecture and Security
Keep the following responsibilities separate:
* SwiftUI user interface.
* Application state and models.
* File selection and file access.
* Media metadata extraction.
* Device discovery.
* Google Cast communication and session management.
* Local HTTP server.
* Playback state and controls.
The UI must not depend directly on Cast protocol implementation details.
Provide suitable abstractions, such as a CastControlling protocol, so that the implementation can be changed without rewriting the interface.
Local HTTP Server Requirements
When implemented, the integrated HTTP server must:
* Expose only the file explicitly selected and authorized by the user.
* Never expose the entire filesystem.
* Support GET requests.
* Support HEAD requests where necessary.
* Support HTTP Range requests and correct 206 Partial Content responses.
* Return correct MIME types and content lengths.
* Support seeking and playback resumption within protocol and device limitations.
* Handle malformed and invalid requests safely.
* Shut down when the Cast session no longer needs it.
* Handle disconnections, errors, and resources safely.
Properly manage:
* File access permissions.
* Security-scoped resources and bookmarks where necessary.
* Local network permissions.
* Required Info.plist declarations.
* Entitlements.
* Server lifecycle and resource cleanup.
Request only the permissions strictly necessary for the application.
Never expose the server to the public Internet or upload the selected video to cloud services.
6. Media Compatibility
For the MVP, prioritize direct playback of formats compatible with Chromecast.
Initial target:
* MP4 container.
* H.264 video.
* AAC audio.
Clearly distinguish between:
1. A file that has been selected and is accessible.
2. A file that macOS can read or analyze.
3. A file that is potentially compatible with the selected Cast device.
4. A file whose playback has actually been verified.
Do not guarantee compatibility without evidence.
Do not introduce FFmpeg or transcoding into the MVP.
They may be evaluated in a later phase only if a concrete requirement arises and the user approves the associated technical and product implications.
7. MVP and Development Phases
Follow the development order below unless the user explicitly approves a change.
ROADMAP.md is the single authority for phase numbers, scope and acceptance criteria; this section states the required technical order and the completion criteria of that same work, without numbering it separately.
The development sequence deliberately places the Local HTTP Server before Cast Communication.
The HTTP server is an independently testable component. Its request handling, file access restrictions, MIME types, and Range support can be implemented and verified locally without requiring a physical Cast device.
Cast Communication can then be implemented against an already established and tested media-serving component. This reduces the number of unknowns during the first end-to-end playback integration.
Foundations
* Analyze macOS, Xcode, Swift, and project configuration.
* Inspect repository structure and build settings.
* Propose a concise initial architecture.
* Create the native macOS SwiftUI project.
* Establish an appropriate modular structure.
* Implement application models and state.
* Implement the main screen.
* Implement native video file selection.
* Implement drag and drop.
* Display the selected file name, size, and format where available.
Completion criteria:
The application builds successfully, allows the user to select or drop a local video file, and displays its basic information.
Device Discovery
* Discover Chromecast and Google TV devices on the local network.
* Display discovered devices.
* Display discovery and connection states.
* Handle device list updates.
* Handle discovery errors and the absence of available devices.
Completion criteria:
Actual available devices are discovered and correctly displayed.
Local HTTP Server
* Implement the integrated local HTTP server.
* Serve only the selected file.
* Implement GET and HEAD requests where required.
* Implement Range requests and correct partial responses.
* Implement correct MIME types and response headers.
* Handle malformed, invalid, and unsatisfiable requests.
* Test file access restrictions.
* Verify behavior using automated local HTTP tests.
* Verify server lifecycle, disconnections, and resource cleanup.
Completion criteria:
The selected file is served correctly over the local network. HTTP behavior, file access restrictions, and Range support are verified through appropriate automated tests.
The server must be independently testable without requiring Cast communication or a physical Cast device.
Cast Communication
* Verify the selected technical solution for Google Cast.
* Implement Cast communication in an isolated component.
* Establish connections to real devices.
* Manage session lifecycle and connection states.
* Handle failures and disconnections.
Completion criteria:
A real connection has been verified with a compatible device.
The Cast implementation must use the previously established HTTP server interface without introducing unnecessary coupling between the two components.
First Playback
* Send the local HTTP URL to the Cast device.
* Start playback of a compatible MP4 H.264/AAC file.
* Handle errors and interruptions.
* Verify actual playback on physical hardware.
Completion criteria:
A real video is playing on a Chromecast or Google TV device using the integrated local HTTP server.
Playback Controls
* Play.
* Pause.
* Stop.
* Forward and backward seeking.
* Playback status.
* Volume control only if supported by the protocol and device.
Completion criteria:
The controls operate the real Cast session and accurately reflect its state.
Do not prematurely implement later phases without a technical reason. If a dependency requires a change in order, explain it and document the reason.
8. User Interface and Behavior
The interface must be native to macOS, minimal, elegant, and understandable to non-technical users.
Prefer native SwiftUI components, consistent spacing, accessible controls, and support for light and dark appearances.
The main screen should clearly organize:
1. Video — selection, drag and drop, file name, and essential information.
2. Device — available devices, selection, and connection status.
3. Playback — primary casting action, controls, and session status.
Do not create decorative controls that appear functional but are not.
Disable unavailable actions and clearly communicate their status.
Provide understandable error messages and useful recovery guidance.
9. Code Quality and Verification
* Write clean, readable, modular Swift.
* Follow Swift language conventions and established project patterns.
* Prefer well-defined types and responsibilities.
* Avoid premature abstractions.
* Handle errors and asynchronous states explicitly.
* Avoid force unwraps and try! unless there is a documented and justified reason.
* Do not suppress warnings without justification.
* Do not add dead code, misleading placeholders, or simulated implementations presented as real.
* Do not rewrite working code without a concrete reason.
* Do not ignore relevant compiler errors or warnings.
* Preserve existing behavior unless the task explicitly requires changing it.
Verification After Changes
After every meaningful implementation increment:
1. Identify the relevant build and test commands.
2. Run the applicable build.
3. Run relevant unit and integration tests.
4. Run additional targeted verification where appropriate.
5. Run GGA when its configured file patterns and rules apply.
6. Inspect the results.
7. Fix failures and repeat the relevant checks.
Do not wait until an entire development phase is complete before testing its components.
Before choosing commands, inspect the actual project structure and available tools, including:
* .xcodeproj.
* .xcworkspace.
* Package.swift.
* Available Xcode schemes and targets.
* Build configurations.
* Installed Xcode and Swift versions.
Never invent scheme names, target names, paths, or successful test results.
If a verification cannot be performed, state exactly what remains unverified and why.
Tests must verify observable behavior and meaningful edge cases, not merely execute code to increase coverage.
Fix the underlying cause of failures instead of weakening or removing tests.
10. Git Branching and Repository Workflow
10.1 Branch Structure
The project uses the following branch hierarchy:
* main: stable, release-ready code.
* dev: integration branch for completed and verified features.
* feature/<descriptive-name>: isolated development branches for individual features or focused tasks.
10.2 Branch Creation and Source
The agent is fully responsible for local Git branch management.
The required workflow is:
main → feature/* → dev → main
Rules:
1. dev must be created from main if it does not already exist.
2. Every new feature branch must be created directly from the latest main.
3. Feature branches must never originate from dev.
4. Use feature/<descriptive-name> for feature branch names.
5. Never develop directly on main or dev.
6. Never require the user to manually create or switch local branches.
Before creating a branch:
* Inspect the current branch.
* Inspect the working tree.
* Check for uncommitted and unrelated changes.
* Verify the source branch.
* Ensure the operation will not overwrite or hide user work.
Do not assume that a branch exists. Verify it.
When remote access is available, inspect whether the local source branch is behind its remote counterpart before creating a feature branch.
Do not silently discard local changes or force synchronization.
10.3 Feature Integration
Completed feature branches are integrated into dev.
Before integration:
1. Verify the feature implementation is complete.
2. Verify relevant builds and tests.
3. Verify GGA where applicable.
4. Inspect differences between the feature branch and dev.
5. Identify potential conflicts and dependencies.
6. Ensure that integration will not discard changes already present in dev.
7. Resolve conflicts carefully when authorized and technically safe.
8. Rerun the relevant tests after conflict resolution.
A feature is not considered integrated merely because its branch exists or its implementation is complete.
The integrated state of dev must be verified separately.
10.4 Feature Dependencies
Because feature branches originate from main, they may not contain work that has already been integrated into dev but has not yet reached main.
The agent must identify these dependencies before implementation or integration.
* Do not silently assume that changes in dev are available in a feature branch.
* Do not create hidden dependencies on unmerged features.
* Do not integrate code that relies on unavailable functionality.
* If a feature requires changes that exist only in dev, report the dependency and propose a safe integration sequence.
* Wait for the required approval when the solution requires promoting dev to main or changing the agreed branch strategy.
Never silently change the feature source branch from main to dev.
10.5 Promotion to Main
The dev branch is promoted to main through a separate integration and release process.
Before promotion:
* Verify the integrated application builds.
* Run the complete applicable automated test suite.
* Verify regression tests.
* Review the changes accumulated in dev.
* Document known limitations and unresolved issues.
* Confirm release readiness.
The promotion of dev to main requires explicit user approval.
10.6 Branch Safety
* Never rewrite shared branch history.
* Never force-push.
* Never discard, overwrite, or silently modify unrelated user changes.
* Never delete branches containing unmerged work.
* Never perform destructive branch operations without explicit approval.
* Always inspect Git status before operations that may affect the working tree.
* Never bypass branch protections or quality checks.
* If the repository state is inconsistent or unsafe, stop and report the issue.
10.7 Branch Completion Reporting
At the end of each feature, report:
* Feature branch name.
* Source branch.
* Proposed target branch.
* Implemented changes.
* Commits created.
* Build and test results.
* GGA result.
* Known limitations and outstanding issues.
* Integration readiness.
11. Commit Policy and Incremental Development
Use small, coherent, reviewable commits.
Do not accumulate an entire development phase or unrelated features into one large commit.
Prefer Conventional Commits:
* feat(ui): add main application window
* feat(video): implement local file selection
* feat(video): display video metadata
* test(video): add metadata extraction tests
* fix(video): handle inaccessible files
* refactor(cast): isolate device discovery service
* docs: update development instructions
* chore(repo): configure development workflow
Commit Rules
1. Each commit must represent one logical, self-contained change.
2. Keep implementation, tests, and documentation changes logically related.
3. Do not include unrelated formatting changes or generated files.
4. Review the staged diff before every commit.
5. Never stage the entire repository blindly with git add . or git add -A.
6. Never include secrets, credentials, local configuration, build artifacts, or unrelated user changes.
7. Ensure relevant tests and quality checks pass before committing.
8. Run GGA before committing whenever its configured rules and file patterns apply.
9. Never bypass Git hooks, GGA, or other quality checks to force a commit.
10. Inspect the actual Git hook configuration and verify that hooks are executable and effective.
Commits Require an Explicit Request
The agent does not commit on its own. Implementation, tests and quality checks finish with
the changes left uncommitted in the working tree, so the user can test the work and give
the final review.
When the user asks for the commit, the agent commits only when:
* The changes belong to the approved task.
* The user has tested or approved the work.
* The staged diff has been inspected.
* Applicable builds and tests pass.
* Applicable GGA checks pass.
* No unrelated user changes are included.
The request also covers integrating the feature branch into dev, unless the user asks for
the commit alone. A commit the user did not request is never created, even when every
check passes.
If a check fails:
1. Investigate the failure.
2. Attempt reasonable fixes within the approved scope.
3. Rerun the relevant checks.
4. Commit only after the required checks pass and the user asks.
Never commit failing or unverified work as though it were complete.
Operations Requiring Approval
The following operations require explicit user approval:
* Creating local commits.
* Pushing commits or branches to any remote.
* Creating or submitting Pull Requests.
* Merging feature branches into dev.
* Merging dev into main.
* Publishing releases or tags.
* Amending, rebasing, resetting, or rewriting existing shared history.
* Destructive Git operations.
Local branch creation, builds, and tests do not require additional approval when compliant with this document.
12. Testing Strategy
Testing is a required part of development, not an optional final step.
Every implemented feature must have appropriate tests covering expected behavior, failure modes, and relevant edge cases.
Use a layered testing strategy.
Unit Tests
Test isolated components, models, services, and functions.
Examples:
* File metadata parsing.
* MIME type determination.
* Media compatibility evaluation.
* Application state transitions.
* HTTP Range parsing.
* URL construction.
* Error mapping.
* Playback state handling.
Unit tests should be deterministic, fast, and independent of physical Cast devices whenever possible.
Integration Tests
Verify that related components work correctly together.
Examples:
* File selection and metadata extraction.
* Application state and UI-facing services.
* HTTP server and local file access.
* Cast session and communication components.
* Discovery results and device models.
Use controlled dependencies and test doubles where appropriate. Do not substitute simulated tests for real integration verification when hardware or actual network behavior is required.
UI Tests
Verify actual user-visible behavior.
Examples:
* Launching the application.
* Opening and dismissing file selection dialogs.
* Dragging and dropping supported files.
* Displaying selected file information.
* Showing discovery and connection states.
* Enabling and disabling actions correctly.
* Displaying errors and recovery states.
End-to-End Tests
Verify complete user workflows wherever practical.
Examples:
* Selecting a local video and displaying its metadata.
* Discovering a compatible device.
* Establishing a Cast session.
* Starting and controlling playback.
* Handling disconnections and recovery.
Clearly distinguish automated end-to-end tests from manual tests requiring physical hardware.
Network and HTTP Tests
Test:
* GET and HEAD requests.
* Valid and invalid Range requests.
* Correct 200, 206, and 416 responses.
* MIME types and content lengths.
* Missing files and denied access.
* Seeking and partial file reads.
* Client disconnections.
* Server shutdown and resource cleanup.
* Attempts to access files other than the authorized selection.
Regression Tests
Whenever a bug is fixed, add a regression test reproducing the original failure whenever practical.
Existing tests must continue to pass after changes.
Performance Tests
Measure relevant performance characteristics, including:
* Metadata extraction time.
* Memory usage.
* CPU usage during important operations.
* HTTP throughput and response times.
* Resource usage during playback.
* Application startup and discovery responsiveness.
Avoid speculative optimization. Measure first, identify bottlenecks, and verify improvements.
Security Tests
Verify:
* File access restrictions.
* Security-scoped resource handling.
* Local network permissions.
* HTTP path and request validation.
* Server exposure boundaries.
* Resource cleanup.
* Malformed input handling.
* Protection against access to files outside the selected file.
Test Quality Rules
* Write tests alongside implementation.
* Test expected behavior and relevant failure conditions.
* Use deterministic fixtures.
* Avoid unnecessary dependence on external services.
* Do not use arbitrary delays or flaky timing assumptions when better synchronization is available.
* Do not weaken assertions merely to make tests pass.
* Do not treat code coverage as proof of correctness.
* Aim for comprehensive coverage of critical business logic and security-sensitive code.
* Establish coverage measurements and reasonable targets after the initial test structure exists.
* Document functionality that cannot be tested automatically and provide a corresponding manual verification procedure.
A feature is not complete merely because it compiles. Its relevant tests and acceptance criteria must pass.
13. GGA and Automated Code Review
GGA is part of the project's quality-control process.
The agent must:
1. Inspect the actual GGA configuration.
2. Read and follow the configured rules file.
3. Understand the configured provider and file patterns.
4. Identify which staged files are eligible for review.
5. Run GGA before committing whenever applicable.
6. Inspect the actual GGA result.
7. Fix reported violations when they are valid and within scope.
8. Rerun GGA after corrections.
Do not assume GGA has reviewed a file merely because GGA was installed or invoked.
Do not report a successful review if:
* No matching files were staged.
* The provider was not actually invoked.
* The review failed.
* The result is incomplete or unavailable.
If GGA cannot run because of provider, network, quota, configuration, or authentication problems, report the exact issue.
Never disable GGA or weaken its rules simply to make a commit pass.
Git Hook Behavior
The pre-commit hook should invoke GGA automatically when a Git commit is attempted, provided the hook is installed and configured correctly.
The agent must not assume that a local hook is present in every clone.
Repository setup must provide a reproducible method to install or configure the required hook.
GGA is not assumed to run automatically after every code edit. The agent must explicitly run the applicable checks during development and before committing.
14. GitHub Actions and Continuous Integration
Configure GitHub Actions to automate build, testing, and quality checks.
The CI workflow must run on relevant Pull Request events and on updates to protected integration branches.
Use macOS runners with compatible Xcode installations for native macOS builds and tests.
The CI pipeline should include, as appropriate:
1. Repository and configuration validation.
2. Swift build verification.
3. Unit tests.
4. Integration tests.
5. UI tests where supported by the runner.
6. Static analysis and linting.
7. Formatting checks.
8. Dependency and license checks.
9. Security-oriented checks.
10. Relevant regression and performance checks.
CI Requirements
* Discover the actual project scheme and configuration.
* Never invent Xcode schemes, targets, or build settings.
* Use reproducible commands.
* Pin or explicitly control important tool versions where practical.
* Keep workflows maintainable.
* Avoid unnecessary third-party actions.
* Do not expose secrets in logs.
* Do not make CI depend on a developer's local machine configuration.
* Cache dependencies only when safe and reliable.
* Separate checks suitable for every Pull Request from slower or hardware-dependent checks.
* Preserve useful diagnostic output.
Do not add meaningless CI jobs or fake test targets merely to make the pipeline appear complete.
When the application project or test targets do not yet exist, configure only the infrastructure that can actually be validated and document what will become available after project creation.
Hardware-Dependent Verification
GitHub-hosted runners cannot be assumed to have access to a physical Chromecast, Google TV device, or the user's local network.
Tests requiring real Cast hardware must be handled through documented manual verification or a dedicated hardware test environment.
Do not mark hardware-dependent functionality as fully verified solely because CI passed.
Branch Protection
Configure repository rules, where supported, to protect main and dev.
Recommended protections:
* Require Pull Requests for changes.
* Require successful mandatory CI checks.
* Require approval before merging.
* Require the branch to be up to date where appropriate.
* Restrict direct pushes to protected branches.
* Prevent force pushes and branch deletion.
Do not assume these protections are active merely because a workflow file exists.
Inspect actual GitHub repository settings when access is available.
If settings cannot be configured through available tools, provide exact instructions for the user to configure them manually.
Never weaken branch protections or bypass required checks to merge failing work.
15. Pull Request and Release Quality Gates
A feature is ready for integration review only when:
* Its scope is clear and limited.
* Its implementation is complete for the stated task.
* Relevant tests have been added or updated.
* The local build succeeds.
* Applicable tests pass.
* Applicable GGA review passes.
* The staged and committed changes have been reviewed.
* Documentation is updated where necessary.
* Known limitations and unverified behavior are documented.
A feature must not be presented as ready for integration while mandatory checks are failing.
Before promoting dev to main, verify:
* The integrated application builds successfully.
* The complete applicable automated test suite passes.
* Regression checks pass.
* Critical user workflows have been verified.
* Outstanding issues and known limitations are documented.
* The release state is consistent with current project goals.
The user retains final approval for all remote pushes and merges.
16. Development Autonomy, Mission Execution, and Delegation
The agent is expected to work autonomously within the scope of an explicitly approved mission.
The purpose of a mission is to let the agent complete a sequence of related tasks without requiring the user to approve every ordinary development step.
16.1 Mission Execution
When a mission includes multiple tasks:
1. Inspect the repository and environment.
2. Understand the mission's scope and acceptance criteria.
3. Break the mission into focused, ordered tasks.
4. Identify dependencies between tasks.
5. Execute the tasks in the appropriate order.
6. Implement one independent feature at a time.
7. Build and test each meaningful increment.
8. Run applicable GGA checks.
9. Leave the verified changes uncommitted for the user's test and final review; commit and integrate into dev only when the user asks.
10. Continue to the next planned task when its dependencies are satisfied.
11. Report meaningful milestones and blockers.
12. Provide a final mission report.
The agent must not stop after every small implementation step or successful test to ask the user whether it may continue. It may continue through the mission and report when the work is ready for the user's test.
The agent must not require the user to manually create branches, run ordinary tests, or authorize normal local development operations.
16.2 Automatic Continuation
After completing a focused task:
* Verify its acceptance criteria.
* Run relevant checks.
* Leave the verified changes ready for the user's test and review, without committing.
* Update the mission's internal task status.
* Proceed to the next planned task if possible.
Continue working until:
* The approved mission is complete.
* A genuine technical blocker prevents further progress.
* An essential user decision is required.
* The mission scope would need to be exceeded.
* An operation requires explicit approval under this document.
Do not stop merely because one task has been completed if the mission explicitly includes additional tasks.
16.3 Parallel Delegation
Use subagents when delegation provides meaningful value.
Parallel delegation is encouraged for independent activities such as:
* Technical research.
* Architecture analysis.
* Test design.
* Code review.
* Security review.
* Reliability review.
* Documentation analysis.
* Independent verification.
The main agent remains responsible for the final implementation and overall result.
Rules:
* Work on only one independent feature at a time.
* Do not allow multiple agents to modify the same files concurrently without explicit coordination.
* Avoid conflicting Git operations by delegated agents.
* Do not allow subagents to commit, push, or merge without the main agent's control.
* Review delegated results critically.
* Verify important conclusions rather than trusting unverified reports.
16.4 Autonomy Boundaries
The agent may autonomously:
* Inspect and analyze the repository.
* Plan and organize approved tasks.
* Create and switch local branches.
* Modify project files within the approved scope.
* Create tests and documentation.
* Run builds and tests.
* Run GGA and other configured checks.
* Fix failures.
* Delegate independent analysis and review.
* Commit and integrate into dev when the user asks, after the required checks pass.
* Continue through the approved mission.
The agent must obtain explicit approval before:
* Pushing to a remote.
* Creating or submitting Pull Requests.
* Merging branches.
* Publishing releases or tags.
* Performing destructive Git operations.
* Making significant architectural decisions outside the approved scope.
* Expanding the product scope.
* Introducing significant external dependencies without prior justification and approval.
16.5 Blocker Handling
When a genuine blocker occurs:
1. Identify the exact problem.
2. Explain what was attempted.
3. Report relevant error messages and verification results.
4. Explain why the agent cannot safely continue.
5. Suggest the smallest reasonable action needed to unblock the mission.
Do not fabricate a workaround, disable quality checks, or claim completion when a blocker remains.
16.6 Reporting
At meaningful milestones and at the end of the mission, communicate in Italian.
The final report must include:
1. Tasks completed.
2. Files created or modified.
3. Implemented functionality.
4. Branches used and their source branches.
5. Local commits created.
6. Build and test commands executed and their actual results.
7. GGA review results.
8. Delegated work and its conclusions, where relevant.
9. CI and Pull Request status, where applicable.
10. Known limitations, blockers, and unverified behavior.
11. Recommended next step.
Never claim that a task or mission is complete if its required acceptance criteria have not been verified.
17. Git, Secrets, and Open-Source Repository
* Respect the project's Apache 2.0 license.
* Do not copy code, dependencies, or assets without checking their licenses.
* Never include credentials, tokens, private certificates, personal data, or sensitive local files.
* Keep .gitignore accurate.
* Exclude build artifacts, temporary files, IDE-specific user state, and sensitive information.
* Do not commit machine-specific paths or local-only configuration unless explicitly required.
* Inspect untracked files before deciding whether they belong in the repository.
* Never stage the entire repository blindly.
* Do not run destructive Git commands without explicit approval.
* Do not modify existing Git history without explicit approval.
* Never bypass Git hooks, GGA, CI, or branch protection to make a change pass.
18. First Assignment — Repository Bootstrap and Phase 1 Preparation
The first mission is to establish a reliable development workflow before implementing application functionality.
The agent must not begin Chromecast communication or implement later development phases.
18.1 Initial Inspection
Before modifying files:
1. Inspect the actual repository structure.
2. Verify macOS, Xcode, and Swift versions.
3. Inspect the current Git branch and working tree.
4. Inspect local and remote branches.
5. Inspect Git remotes and tracking configuration.
6. Inspect existing Git hooks and hook configuration.
7. Inspect .gitignore, AGENTS.md, and GGA configuration.
8. Inspect existing GitHub Actions workflows.
9. Check whether an Xcode project, workspace, or Swift package already exists.
10. Identify available Xcode schemes, targets, and build configurations if present.
Do not assume the repository is empty or clean.
Do not overwrite or discard existing user changes.
18.2 Establish the Branch Structure
The intended structure is:
* main: stable branch.
* dev: integration branch created from main.
* feature/<descriptive-name>: development branch created directly from main.
If dev does not exist locally:
1. Verify the working tree is safe.
2. Verify the current main state.
3. Create local dev from main.
4. Do not push it without explicit approval.
Create the initial repository-bootstrap feature branch directly from main.
Do not implement application functionality directly on main or dev.
Do not create remote branches without explicit approval.
18.3 Repository Infrastructure
Inspect and establish, where necessary:
* A suitable .gitignore.
* A reproducible GGA configuration.
* A reproducible method for installing or configuring the pre-commit hook.
* A maintainable GitHub Actions CI workflow.
* A concise CONTRIBUTING.md.
* Appropriate repository documentation.
Inspect every existing untracked file before staging it.
Do not delete local-only files without explicit approval.
Do not commit temporary scratch directories or machine-specific artifacts.
Preserve the configured GGA provider unless a concrete technical problem requires a proposed change.
Verify that GGA actually reviews eligible staged files. If necessary, perform a controlled test in an isolated temporary Git repository rather than introducing intentional violations into the real project history.
If the provider cannot be verified, report the issue instead of claiming that GGA works.
18.4 Bootstrap Verification
Run all checks that are actually applicable to the existing repository.
Do not invent an Xcode scheme, test target, application target, or successful test result.
Verify the repository configuration, Git branch structure, hook behavior, GGA behavior, and CI configuration to the extent possible.
18.5 Bootstrap Commit
If all applicable checks pass and the user asks for the commit:
* Review the staged diff.
* Stage only files belonging to the repository-bootstrap task.
* Create small, coherent local commits.
* Use an appropriate Conventional Commit message, such as chore(repo): establish development workflow and CI infrastructure.
Do not push or merge.
18.6 Phase 1 Preparation
After the repository infrastructure is established:
1. Inspect the actual project state again.
2. Identify what is still missing for Phase 1.
3. Propose the initial SwiftUI application architecture.
4. Identify the first focused implementation task.
5. Report the plan and any important decisions requiring user approval.
Do not silently expand the scope of the bootstrap mission into the complete application implementation.
Proceed with application development only within the approved mission scope.
19. Final Operating Principle
The agent is responsible for carrying out approved development work, including local Git management, implementation, testing, quality checks, delegation, and committing on request.
The user should define goals, approve significant decisions, review milestones, and authorize remote operations.
Do not turn ordinary development steps into repeated approval requests.
Work autonomously, incrementally, transparently, and safely.
Correctness and verifiable results always take priority over speed or the appearance of progress.
20. User Autonomy and Manual Operations
All restrictions, approval requirements, and workflow rules defined in this document govern the AI agent's actions only. They do not restrict the user's actions or decisions.
The user retains full control and autonomy over the repository and may independently perform any operation at any time, including:
* Creating, switching, renaming, and deleting branches.
* Committing, amending, cherry-picking, rebasing, and reverting commits.
* Pushing and pulling changes.
* Opening, reviewing, merging, and closing pull requests.
* Creating releases and tags.
* Modifying repository files, configuration, workflows, and project structure.
The agent must never interpret an operation manually performed by the user as a violation of these instructions or as an operation requiring retroactive approval.
The agent must adapt to the actual repository state after user-performed operations. It must inspect the current Git state before acting and must not assume that the user follows the agent's prescribed workflow.
When the user explicitly requests a manual operation or chooses a workflow different from the one prescribed here, the user's instructions take precedence over the agent's default workflow.
These instructions govern the agent, not the user.
