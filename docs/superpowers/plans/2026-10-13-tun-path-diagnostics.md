# TUN Current-Path Diagnostics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a native five-stage current-path diagnostic strip above ClashX Dashboard.

**Architecture:** A standalone service performs bounded, read-only probes and publishes immutable snapshots. A native AppKit view renders those snapshots above the unchanged third-party Dashboard web view. Small pure functions isolate stage dependency, TUN evidence, chain selection, and sanitization for deterministic tests.

**Tech Stack:** Swift 5, AppKit, Foundation networking, SystemConfiguration, XCTest, existing Clash controller API.

---

## File Structure

- Create `ClashX/Diagnostics/PathDiagnosticModels.swift`: diagnostic types and dependency rules.
- Create `ClashX/Diagnostics/PathDiagnosticsService.swift`: controller, interface, DNS, chain, delay, and HTTPS probes.
- Create `ClashX/Diagnostics/PathDiagnosticsView.swift`: native strip and stage cells.
- Create `ClashX/Diagnostics/PathDiagnosticPopoverController.swift`: evidence popover.
- Modify `ClashX/ViewControllers/ClashWebViewContoller.swift`: lifecycle and split layout.
- Modify `ClashX/General/ApiRequest.swift`: result-bearing controller helpers needed by diagnostics.
- Modify `ClashX/Models/ClashConfig.swift`: optional TUN fields without breaking legacy responses.
- Modify `ClashX.xcodeproj/project.pbxproj`: add sources and test target membership.
- Create `ClashXTests/PathDiagnosticModelsTests.swift`: pure behavior tests.
- Create `ClashXTests/PathDiagnosticsServiceTests.swift`: orchestration tests with injected probes.

### Task 1: Diagnostic Domain Model

- [ ] Create an XCTest target named `ClashXTests` and add `PathDiagnosticModelsTests.swift`.
- [ ] Write failing tests asserting stage order, upstream blocking, TUN-inactive continuation, leaf selection from `chains`, and secret sanitization.
- [ ] Run `xcodebuild test -workspace ClashX.xcworkspace -scheme ClashX -destination 'platform=macOS'`; expect missing diagnostic symbols.
- [ ] Implement `PathDiagnosticStage`, `PathDiagnosticStatus`, `PathDiagnosticResult`, and `PathDiagnosticsSnapshot` in `PathDiagnosticModels.swift`.
- [ ] Implement pure helpers:

```swift
static func blockedResults(after failedStage: PathDiagnosticStage,
                           existing: [PathDiagnosticStage: PathDiagnosticResult])
    -> [PathDiagnosticStage: PathDiagnosticResult]
static func exitNode(from chains: [String], groupNames: Set<String>) -> String?
static func sanitized(_ message: String) -> String
```

- [ ] Re-run model tests; expect PASS.
- [ ] Commit: `feat: add path diagnostic model`.

### Task 2: Probe Service

- [ ] Write failing service tests using an injected `PathDiagnosticsProbing` fake for: core failure blocking, inactive TUN allowing later probes, DNS failure blocking Internet, stale run suppression, and independent exit-node delay failure.
- [ ] Extend `ClashConfig` with optional decoded TUN state so legacy controller JSON remains valid.
- [ ] Add result-bearing `ApiRequest` helpers for raw config, connection chains, and node delay. Each completion returns `Result<Value, Error>` and has a finite timeout.
- [ ] Implement `PathDiagnosticsService` with:

```swift
func run(completion: @escaping (PathDiagnosticsSnapshot) -> Void)
func cancel()
```

- [ ] Implement read-only probes: controller response; configured TUN state plus route/interface evidence; `getaddrinfo` resolution; connection `chains` observation; node delay; cache-disabled HTTPS response.
- [ ] Ensure every callback checks the current run UUID and publishes UI callbacks on main queue.
- [ ] Run service tests; expect PASS.
- [ ] Commit: `feat: add current path probes`.

### Task 3: Native Diagnostic Strip

- [ ] Write view-model tests for titles and summaries of all five statuses.
- [ ] Implement `PathDiagnosticStageView` using dot, title, detail, and duration labels; express state through text and color.
- [ ] Implement `PathDiagnosticsView` with five stages, dependency arrows, and `Run Again` button.
- [ ] Implement `PathDiagnosticPopoverController` to show sanitized evidence and timestamp.
- [ ] Use system semantic colors and constraints compatible with macOS 10.12.
- [ ] Run view-model tests; expect PASS.
- [ ] Commit: `feat: render path diagnostics strip`.

### Task 4: Dashboard Integration

- [ ] Add `PathDiagnosticsView` above `CustomWKWebView` in `ClashWebViewContoller`.
- [ ] Keep the strip at fixed height and web view filling remaining bounds at the existing 920 x 580 minimum size.
- [ ] Start diagnostics in `viewWillAppear`, cancel on close/deinit, and refresh on `.systemNetworkStatusDidChange` and `.systemNetworkStatusIPUpdate` with debounce.
- [ ] Wire `Run Again` to `PathDiagnosticsService.run`.
- [ ] Verify custom `webviewUrl`, JS bridge, draggable title area, reload notification, and resize behavior remain intact.
- [ ] Build with `xcodebuild -workspace ClashX.xcworkspace -scheme ClashX -configuration Debug build`; expect `BUILD SUCCEEDED`.
- [ ] Commit: `feat: show path diagnostics in dashboard`.

### Task 5: Runtime Verification

- [ ] Launch Debug build and open Dashboard with TUN disabled; expect TUN `inactive` while DNS and Internet still resolve.
- [ ] Enable TUN; expect concrete interface/route evidence rather than generic `utun exists` output.
- [ ] Stop Clash core; expect Core `failed` and dependent stages `blocked`.
- [ ] Use an invalid DNS configuration; expect DNS `failed` and Internet `blocked`.
- [ ] Select an unreachable node; expect observed node name with failed delay or Internet evidence.
- [ ] Restore working config and run again; expect five evidence-backed results with no proxy/config mutation.
- [ ] Run full tests and `git diff --check`.
- [ ] Commit any verification-only corrections as `fix: harden path diagnostics`.
