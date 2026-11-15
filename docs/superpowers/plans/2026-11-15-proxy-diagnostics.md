# Proxy Diagnostics Implementation Plan

**Goal:** Verify actual proxy requests and show the observed overlay connection path after the latency.

**Architecture:** Foundation-only probe and path classifiers, called by a bounded background batch. AppKit integration applies snapshot-matched results on the main queue.

**Tech Stack:** Swift 5, Foundation, Darwin, ss-local, system curl, Tailscale/ZeroTier CLI; existing Xcode workspace and a focused SwiftPM test target.

**Spec:** ../specs/2026-11-15-proxy-diagnostics-design.md

## Global Constraints

- Preserve production settings and full SSR options; no dependencies or remote writes.
- HTTPS 204 verification, ten-second request deadline, one retry on failure, bounded helper lifecycle.
- No direct/relay inference from DNS naming or Tailscale home DERP alone.
- Unknown/offline/ambiguous overlay states must remain unknown.

## Review Focus

- Ambient proxy variables or curl configuration bypassing the test profile.
- Child processes/configurations surviving failures or application exit.
- Concurrent profile edits, reloads, sorting and repeated runs.
- Missing CLIs, IPv6 and ZeroTier bridging returning misleading labels.
- Cached success after a new failure, including all-failed batches.

## Tasks

1. [x] Add Foundation tests for HTTPS response validation, subprocess timeout/cleanup, Tailscale current/idle/offline states and ZeroTier peer mapping/direct/relay. Later state/association/order/parser regressions verified RED→GREEN.
2. [x] Implement `Diagnostics/ProxyProbe.swift`, `OverlayConnection.swift`, `ProxyTestResult.swift` and a bounded `ProxyTestBatch`. `swift test`: 19 passing tests.
3. [x] Replace `ConnectTestigManager`'s ICMP/TCP dispatch with snapshot-based proxy tests. Add transient results to ServerProfile and preserve them on reload. Update menu/setting copy and status tooltips.
4. [x] Register sources in Xcode, add repeatable build/run and test entrypoints. Build with macOS 14 deployment override (existing login helper specifies unsupported 10.12).
5. [x] Exercise actual profiles with the production probe/classifier, verify no production settings change or temporary helpers remain, review changes, and provide a local built app.

## Progress

- Baseline: clean develop at 29bd6f1, new branch `fix/proxy-latency-path`.
- Baseline build passes with `MACOSX_DEPLOYMENT_TARGET=14.0`. Unmodified default build fails because the login helper targets 10.12 on the installed SDK.
- Work remains in the user's requested fresh checkout; no unrelated changes were present.
- Runtime: true HTTPS requests succeed for Tailscale linode, linodejp, conoha and ZeroTier linodejp; vpn fails the real request.
- macOS 27.2.1 ARP redaction reproduced with compiled Swift; explicit ZeroTier association added and validated against live CLI state. No system privacy/developer-account changes.
- Author review found menu refresh overwriting live profile edits and malformed MAC parsing; both fixed with RED→GREEN regressions.
- Independent review was attempted but unavailable due tool usage limit. Author review completed instead.
- Final verification: 19 XCTest cases and the real ServerProfile/AppKit menu model check pass; Debug and Release builds succeed. The arm64 Release app was copied, ad-hoc signed, verified with codesign, and zipped for delivery. No full GUI launch was performed, preserving the installed client's session.
