# Mihomo Migration and Low-Memory Runtime Design

## Goal

Add the maintained Mihomo sidecar without removing the embedded 2022 Clash core. macOS 13 and newer select Mihomo; older supported macOS releases keep the legacy core. Preserve the current-path diagnostics feature and add bounded health checks and deterministic Dashboard cleanup.

## Migration Strategy

Keep the existing application and deployment target as the compatibility baseline. Move only ownership wrappers into `ClashX/CoreRuntime/LegacyCore/`, add the new implementation under `ClashX/CoreRuntime/MihomoCore/`, and expose both through one `CoreRuntime` interface. `CoreRuntimeSelector` chooses Mihomo on macOS 13+ and the legacy embedded core below macOS 13. A developer override may force either implementation for testing.

The Mihomo implementation uses the official standalone executable launched through the privileged helper. It does not embed Mihomo as a Go `c-archive`. The stable Mihomo release tag is pinned during packaging, both macOS architectures are downloaded, release checksums are verified, and the packaged executable is validated before launch. The legacy binary and its entry points remain available and are not deleted.

## Core Lifecycle

The application owns one logical selected-core instance. On macOS 13+ its Mihomo lifecycle is:

```text
App startup
  -> resolve and verify bundled core
  -> verify privileged helper
  -> compose effective config
  -> terminate stale managed Mihomo process
  -> start Mihomo through helper
  -> wait for controller readiness
  -> publish running state
```

Startup errors remain separated into core verification, helper installation, config composition, process launch, and controller readiness. The application must not report a running core from process creation alone.

App termination stops only the Mihomo process identified by the managed launchd label. Config reload uses the controller and official process manager behavior from upstream.

## TUN Stack Default

The effective configuration defaults to:

```yaml
tun:
  stack: system
```

The override is applied only when TUN exists and `stack` is absent or empty. An explicit user value such as `gvisor` is preserved.

The UI keeps the stack visible and switchable. `system` is recommended for lower memory and native macOS TCP behavior. `gvisor` remains available for workloads whose UDP, fragmentation, or userspace-stack behavior is more compatible with it.

## Health-Check Queue

All user-triggered bulk tests use one `ProxyHealthCheckQueue` with a hard maximum of three concurrent operations.

Requirements:

- individual proxy delay requests, provider health checks, and group health checks share the same concurrency budget during a bulk run;
- duplicate targets in the same batch are coalesced;
- FIFO order is preserved for queued targets;
- cancelling a batch prevents queued operations from starting and ignores late results from the cancelled generation;
- a new full benchmark cancels the previous full benchmark;
- automatic network-change checks use the same queue and cannot bypass the limit;
- UI state distinguishes queued, running, completed, failed, and cancelled work.

Single explicit user checks may use the queue immediately but never raise global concurrency above three.

## Dashboard Lifecycle

The Dashboard controller owns an optional `WKWebView`. Opening the Dashboard creates and configures it. Closing the Dashboard performs, in order:

1. cancel current-path diagnostic work;
2. stop web loading;
3. remove navigation and UI delegates;
4. remove registered scripts and message handlers;
5. load a blank page and remove the web view from its superview;
6. set the web view reference to `nil`;
7. release the Dashboard content controller from the window controller.

Reopening creates a fresh `WKWebView`. Website data is not globally erased on every close; releasing runtime objects is distinct from deleting user data.

## Current-Path Diagnostics

Recreate the native five-stage strip above the new Dashboard:

```text
Mihomo Core -> TUN / Route -> DNS -> Exit Node -> Internet
```

Use the new kernel state and Mihomo controller responses as evidence. Preserve the existing status semantics, sanitized details, retry action, and network-change refresh. Closing the Dashboard cancels active diagnostic work.

## Compatibility and Rollback

- Existing configuration files remain in the current ClashX location.
- Explicit proxy, DNS, TUN, and stack settings are preserved.
- macOS 10.13 through 12 continue using the legacy embedded core.
- macOS 13+ use Mihomo by default; both Intel and Apple Silicon binaries are packaged.
- The two implementations live in independent folders and can be switched by the selector without deleting either one.
- No automatic replacement of a user's downloaded Alpha core occurs.

## Verification

Automated verification covers:

- effective config adds `system` only when stack is missing;
- explicit `gvisor` survives composition;
- health-check concurrency never exceeds three;
- duplicate targets execute once;
- cancelled batches do not start queued work or publish stale state;
- Dashboard cleanup releases its web view and diagnostics task;
- diagnostic stage dependency and sanitization behavior.

Build verification covers arm64 and x86_64 compilation plus the packaged Mihomo checksum.

Runtime verification requires:

- controller reports the pinned Mihomo version;
- ordinary system-proxy mode reaches the Internet;
- TUN `system` mode reaches the Internet and restores routes after shutdown;
- one UDP workload succeeds;
- bulk benchmark visibly caps active requests at three;
- Dashboard WebContent memory drops after close and returns only after reopen;
- induced core, route, DNS, node, and Internet failures appear at the correct diagnostic stage.

Build success alone is not runtime completion.

## Out of Scope

- Changing the user's benchmark URL.
- Removing `gvisor` support.
- Automatically rewriting explicit user TUN settings.
- Following Mihomo Alpha releases by default.
- Redesigning unrelated upstream UI.
