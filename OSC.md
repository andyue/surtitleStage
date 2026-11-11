# OSC Control

Open the **OSC** tab in the lower-left pane and press **Start OSC**. The default UDP port is **8000**; a different port from 1–65535 can be entered while stopped. The port is remembered on this Mac, but receiving must be started manually each app session. This is an application setting; existing project files are unchanged.

Send OSC over IPv4 UDP to this Mac's IP address (or `127.0.0.1` on the same Mac). The receiver listens on all IPv4 interfaces. Only enable it on a trusted show network: OSC commands have no authentication. The status shows bind failures, rejected packets, and received commands.

| Address | Arguments | Effect |
| --- | --- | --- |
| `/subtitle/go` | None | Existing GO behavior, including cue fades |
| `/subtitle/previous` | None | Existing Previous behavior |
| `/subtitle/blackout` | int32 `1` / `0` | Blackout on / restore |
| `/subtitle/blackout` | None | Toggle: first press blacks out, next press restores |
| `/subtitle/blackout` | OSC `T` / `F` | `T`: on; `F`: restore |
| `/subtitle/cue/{UUID}` | None | Show the specified cue, preserving editor selection |

Copy the selected cue's full OSC address from the OSC tab. Cue numbers and row indices are not identifiers. Jump uses the same behavior as Show Selected, including fade-in; blackout remains unchanged. Unknown UUIDs do not change playback. Explicit blackout on/off commands are idempotent. For a single OSC button, send `/subtitle/blackout` with no arguments once per press to toggle; do not also send it on release.

Messages require a type-tag string (`,` for no arguments). This implementation supports exact addresses and immediate bundles (`#bundle`, timetag 1), in packet order. Scheduled bundles, wildcard addresses, unsupported types and malformed packets are rejected before execution. Limits: 65,507 bytes, 128 packet nodes and eight nesting levels. The binary format follows the [OSC specification](https://opensoundcontrol.stanford.edu/spec-1_0.html).

Playback executes on the main actor through the existing store. Network reads and parsing use a serial background queue with backpressure; stopping invalidates pending callbacks. Commands received while project operations are busy are ignored. Existing transition guards still apply (GO/Previous during an active fade-out are ignored, as with local controls).

UDP has no delivery, deduplication, or acknowledgement guarantee. This version does not implement OSC feedback, scheduling, independent layer navigation, or automatic reconnect control. Test the actual controller and show network before production use.

## Acceptance status — 2026-10-18

The user reports that the actual OSC controller and show-network operation are OK for v0.2.2. This does not imply support for independent layer navigation or the other unsupported features listed above. Multi-display endurance and fade smoothness across refresh rates remain unverified; see SURTITLE_WORKFLOW_VERIFICATION.md.
