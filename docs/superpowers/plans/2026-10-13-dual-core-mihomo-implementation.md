# Dual-Core Mihomo Implementation Plan

**Goal:** Keep old macOS releases on the existing embedded Clash core and use a separately packaged Mihomo sidecar on macOS 13+, while reducing health-check pressure and releasing Dashboard web memory.

## 1. Runtime boundary and selection

- Add tests for OS-version and developer-override selection.
- Add `CoreRuntime`, `CoreRuntimeKind`, and `CoreRuntimeSelector` under `ClashX/CoreRuntime/`.
- Put legacy initialization behind `LegacyCoreRuntime` in `CoreRuntime/LegacyCore/`; do not remove the Go bridge.
- Add `MihomoCoreRuntime` in `CoreRuntime/MihomoCore/`.
- Change app startup/reload/shutdown call sites to use the selected runtime.

## 2. Mihomo packaging and privileged lifecycle

- Pin the stable Mihomo version and checksums in a manifest.
- Add a packaging script that downloads arm64 and amd64 release assets, verifies checksums, builds a universal executable, and stores it only in the Mihomo resource folder.
- Add helper messages for start, stop, and status of the Mihomo launchd job.
- Verify the bundled executable before launch and wait for controller readiness before publishing running state.
- Keep legacy paths and resources untouched.

## 3. Configuration compatibility

- Add tests for effective TUN stack composition.
- For Mihomo only, inject `tun.stack: system` when TUN exists and stack is missing or empty.
- Preserve explicit `system`, `gvisor`, or other supported values.
- Do not rewrite the user's source configuration file.

## 4. Health-check queue

- Add deterministic queue tests proving a maximum of three active checks, FIFO start order, deduplication, cancellation, and stale-result suppression.
- Route bulk, automatic network-change, provider, group, and node checks through one queue.
- Keep the full-test command but enqueue all work with concurrency three.

## 5. Dashboard lifecycle and diagnostics

- Make the web view optional and create it when the Dashboard opens.
- On close, cancel diagnostics, stop loading, detach delegates and bridge handlers, remove the web view, and nil all strong references.
- Release the Dashboard content controller from its window controller.
- Keep the current-path diagnostic strip and recreate a fresh web view on reopen.

## 6. Verification

- Run focused Swift tests for selection, config composition, queue behavior, diagnostics, and Dashboard teardown helpers.
- Build the current minimum-macOS target plus macOS 13 runtime code for both architectures.
- Validate the bundled Mihomo checksum and executable architectures.
- Runtime-check legacy startup on macOS 12 or a compatible VM, and Mihomo controller readiness, system proxy, TUN system stack, UDP, route restoration, queue cap, and Dashboard process release on macOS 13+.
- Treat unavailable cross-version runtime checks as explicit unverified gates, not as completion.
