# ZG Overlay Relay Server

This is an optional fallback bridge for builds where the signer breaks the App Group entitlement.

The broadcast extension sends:

```text
POST /push/zg-default/state
POST /push/zg-default/frame
```

The main app/PiP preview reads:

```text
GET /latest/zg-default/state
GET /latest/zg-default/frame
```

## Run locally

```bash
npm start
```

Health check:

```text
http://localhost:8080/health
```

For iPhone testing, deploy it to a public HTTPS host such as Render, Railway, Fly.io, or your VPS.

Then set the same URL in:

```text
ZGReplayVisualOverlay/Sources/OverlaySettings.swift
ZGReplayVisualOverlayBroadcast/Sources/SampleHandler.swift
```

Example:

```swift
static let relayBaseURL = "https://your-zg-relay.onrender.com"
```
