# Logic Pro MCP — Project Guide

## What this is

A Swift MCP (Model Context Protocol) server that lets Claude control Logic Pro on macOS. It exposes tools for transport, tracks, MIDI, mixing, editing, and navigation. The server runs as a background process; Claude Desktop connects to it via the MCP stdio transport.

## Build & run

```bash
# Debug build (fast, used during development)
swift build

# Release build — REQUIRED for the live MCP server
swift package clean && swift build -c release

# The server binary Claude Desktop uses:
.build/release/LogicProMCP          # symlink → .build/x86_64-apple-macosx/release/
```

`rm -rf .build/release` does not clean the real artifacts because it is a symlink. Use `swift package clean` for a full clean.

After rebuilding, kill the running server so Claude Desktop spawns the new binary:
```bash
pkill -f LogicProMCP
```
Then reconnect with `/mcp` in the Claude Desktop chat.

## Claude Desktop config

```
~/Library/Application Support/Claude/claude_desktop_config.json
```

Points to `.build/release/LogicProMCP`. Changes there take effect on next Claude Desktop restart.

## Architecture

```
MCP tool call
  └── Dispatcher (one per tool: TrackDispatcher, MIDIDispatcher, …)
        └── ChannelRouter.route(operation:params:)
              └── Channel (tries in order until one succeeds)
```

### Channels

| ID | Type | Used for |
|---|---|---|
| `.cgEvent` | CGEventChannel | Keyboard shortcuts posted to Logic Pro's PID via `postToPid` |
| `.accessibility` | AccessibilityChannel | AX tree reads/writes (arm, mute, solo, track names, …) |
| `.coreMIDI` | CoreMIDIChannel | MIDI note/CC/MMC delivery |
| `.appleScript` | AppleScriptChannel | Project lifecycle + true non-toggle stop |
| `.osc` | OSCChannel | Volume/pan (not always available) |

### Key routing decisions

- `transport.stop` → CGEvent (Space key — **toggle**, stops if playing)
- `transport.force_stop` → AppleScript only (`tell Logic Pro to stop` — **always** stops, not a toggle). Use this for setup/teardown in `recordPattern`.
- `transport.record` → CGEvent (R key), with CGEvent sleep of 50ms before key post.
- `track.set_arm/mute/solo` → AccessibilityChannel first; reads AXCheckBox value before pressing to avoid redundant toggles.

## Critical gotchas

### CGEvent activation overhead
`CGEventChannel.execute` calls `app.activate()` then sleeps **50ms** before posting the key. Total round-trip from `router.route()` call to key delivered: ~52ms.

### `transport.force_stop` vs `transport.stop`
Space bar is a **play/stop toggle**. If Logic is stopped, Space starts playback. Always use `force_stop` (AppleScript) when you need a guaranteed stop from an unknown state.

### AXCheckBox vs AXButton
Logic Pro's arm/mute/solo buttons are `AXCheckBox` elements, not `AXButton`. Their value is an `NSNumber` (0 = off, 1 = on). `setTrackToggle` reads this before pressing to avoid unintended state flips.

### Piano Roll disrupts AX navigation
When the Piano Roll is open as an embedded pane, `getTrackHeaders()` navigates to the wrong element and `track.set_arm` silently fails (R then starts playback instead of recording). Use `AXLogicProElements.verifyTrackHeadersAccessible()` to detect this and close the Piano Roll first.

### Logic Pro count-in
If count-in is enabled in Logic Pro preferences, recording starts N bars **after** R is pressed. This offsets all recorded notes. Keep count-in **disabled** when using `record_pattern`.

## Beat-accurate MIDI recording (`record_pattern`)

### Timing model
Setting `t0` **before** calling `router.route(operation: "transport.record")` and shifting all note targets by `recordingStartMs` compensates for:

1. CGEventChannel's 50ms activation sleep (R key posted ~50ms after the route call starts)
2. Logic Pro's ~45ms processing delay from R key to actual recording start

```
t0 set here
│
├─ route("transport.record") called → returns ~52ms later (R key posted at t0+50ms)
│
└─ recording starts at ≈ t0 + 95ms
   ├─ first kick target: t0 + 0ms*beatMs + 95ms = t0 + 95ms  → lands at ~0ms in recording ✓
   └─ subsequent notes offset by same 95ms, preserving relative timing
```

**Calibrated value: `recordingStartMs = 95.0` ms** (specific to this machine).

If timing drifts (e.g. after OS updates), tune this constant:
- Notes land **before** beat 1 → **increase** `recordingStartMs`
- Notes land **after** beat 1 → **decrease** `recordingStartMs`
- Expected search space: 85–105ms

The end-of-recording wait also uses this offset so the stop fires at the right time:
```swift
let endNs = UInt64((totalBeats * beatMs + recordingStartMs) * 1_000_000)
```

### Do not use auto-quantize
`record_pattern` deliberately omits auto-quantize (Q key after recording). Rhythms like shuffle require non-quantized timing. Notes land close enough to the grid that manual quantize works when needed.
