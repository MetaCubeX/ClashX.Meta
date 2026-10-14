# TUN Current-Path Diagnostics Design

## Goal

Add a native diagnostics strip to the top of the Dashboard window so a user can identify which stage caused connectivity loss after enabling TUN mode.

The strip reports evidence for one current traffic path. It does not attempt to visualize every configured proxy or replace the existing proxy list.

## User Interface

The Dashboard window contains two vertically arranged regions:

1. A native AppKit diagnostics strip at the top.
2. The existing web Dashboard below it.

The strip shows five ordered stages:

```text
Clash Core -> TUN / Route -> DNS -> Exit Node -> Internet
```

Each stage has a status dot, title, short detail, and elapsed time when available. Arrows show dependency order. Statuses are:

- `checking`: yellow, probe running.
- `healthy`: green, probe succeeded.
- `failed`: red, probe failed with direct evidence.
- `blocked`: gray, not tested because an upstream stage failed.
- `inactive`: gray, feature is disabled or no applicable data exists.

Clicking a stage opens a compact detail popover containing the exact observed value, error, and probe time. A `Run Again` button starts a fresh diagnostic run. The strip runs automatically when the Dashboard opens and when macOS reports a network change.

## Diagnostic Semantics

### Clash Core

Healthy when the local Clash controller responds and its configuration can be read. Failure detail distinguishes core-not-running, controller-unreachable, authentication failure, and malformed response.

### TUN / Route

Inactive when TUN is disabled in the controller configuration. When enabled, the probe checks both an active TUN interface and the effective route used for the Internet probe destination. It reports interface and route evidence separately. A generic `utun` interface alone is insufficient because other VPN software can create one.

### DNS

Resolves the hostname used by the Internet probe through the system resolver. The result records resolved addresses and elapsed time. It does not claim DNS health from cached Clash configuration alone.

### Exit Node

Uses the Clash connections API `chains` field from traffic generated during the diagnostic run. The last non-group proxy in the observed chain is displayed as the exit node. If no chain can be captured, status remains `inactive` with `No active chain observed`; the UI must not guess from a selected proxy group.

When a concrete node is observed, its delay endpoint is queried. Delay failure marks this stage failed without rewriting the user's selected proxy.

### Internet

Performs a small HTTPS request to the configured benchmark URL, with a bounded timeout and cache disabled. Success requires an HTTP response, not only TCP connect. Failure detail preserves the URL loading error category without exposing secrets.

## Probe Flow

`PathDiagnosticsService` owns one run at a time and emits immutable snapshots to `PathDiagnosticsViewModel`.

```text
Dashboard opens / network changes / user retries
  -> cancel older run
  -> probe Core
  -> probe TUN and route
  -> probe DNS
  -> start Internet request and observe connection chain
  -> probe observed exit-node delay
  -> publish final snapshot
```

If Core fails, all later stages become blocked. If TUN is inactive, DNS, Exit Node, and Internet still run so non-TUN connectivity remains diagnosable. DNS failure blocks the hostname-based Internet request. Exit-node delay and Internet reachability are reported independently after a chain is observed.

All UI updates occur on the main queue. Probe work uses a dedicated serial queue. Starting a new run cancels callbacks from the previous run through a run identifier.

## Components

- `PathDiagnosticStage`: stage identity.
- `PathDiagnosticStatus`: checking, healthy, failed, blocked, inactive.
- `PathDiagnosticResult`: status, summary, detail, duration, timestamp.
- `PathDiagnosticsSnapshot`: ordered results plus run identifier.
- `PathDiagnosticsService`: orchestration and system/controller probes.
- `PathDiagnosticsViewModel`: converts snapshots into display state.
- `PathDiagnosticsView`: native AppKit strip, stage buttons, arrows, and retry button.
- `PathDiagnosticPopoverController`: evidence display for one stage.
- `ClashWebViewContoller`: lays out the strip above the existing web view and owns the service lifecycle.

No diagnostic component changes proxy selection, routes, DNS settings, or TUN state.

## Dashboard Compatibility

The feature does not modify or inject code into the bundled third-party Dashboard. It works with both the bundled `/ui/` page and a user-defined `webviewUrl`. The web view keeps its existing bridge and behavior; only its frame moves below the native strip.

The strip uses standard AppKit colors with accessibility contrast and supports existing macOS appearance changes. Stage meaning is also expressed in text, not color alone.

## Error Handling and Privacy

- Every probe has a finite timeout.
- Expected network failures become stage results, not assertions or app crashes.
- Secrets, authorization headers, complete configuration payloads, and proxy credentials never enter details or logs.
- Logs contain run identifier, stage, status, duration, and sanitized error category.
- Closing the Dashboard cancels active probes.

## Verification

Unit tests cover:

- stage dependency and blocked-state calculation;
- stale-run cancellation;
- active-chain leaf selection;
- TUN-disabled behavior;
- error sanitization;
- view-model labels for every status.

Integration checks cover:

- Dashboard layout at its minimum size;
- automatic run on open and network change;
- manual retry;
- core stopped;
- TUN disabled;
- DNS failure;
- unreachable proxy node;
- Internet failure after successful DNS;
- remote `webviewUrl` compatibility.

Completion requires a successful build plus manual validation that induced failures appear at the correct stage. A successful build alone is not runtime verification.

## Scope Exclusions

- Editing TUN configuration.
- Automatically changing nodes.
- Full proxy topology visualization.
- Persistent diagnostic history.
- Packet capture.
- Modifying the third-party Dashboard project.
