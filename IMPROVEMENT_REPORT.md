# V3 improvement report

## Main request

Make the blue button act like a screen recording / screen sharing function, similar to WhatsApp screen sharing.

## Implemented

- Added animated **Created by ZG** entry screen with private code `777`.
- Rebuilt the app into three pages: **Live**, **Assist**, and **Status**.
- Added feature tiles for live scanner state, scan route, prediction style, and hold window.
- Added bubble-style ZG branding for a less plain visual design.
- Replaced small picker square with a full-width visible button.
- The visible button says **START SCREEN RECORDING**.
- The ReplayKit picker now has an explicit full-size SwiftUI frame and UIKit hit-test forwarding, so tapping anywhere on the blue button opens Apple's broadcast UI.
- Added Floating Preview using `AVPictureInPictureController` and `AVSampleBufferDisplayLayer`.
- Fixed Floating Preview video buffer orientation so text should no longer render upside down.
- Made the app interface darker and added bottom credit `created by zav G`.
- Added **START SCANNER** and **STOP / HOLD** buttons.
- Added hold-last-scan timing so the latest prediction remains visible while moving the PiP window.
- Added PiP play/pause support for scanner resume/hold.
- Added four scan routes: Auto Hybrid, Guide Lock, Ball Geometry, Corner Lock.
- Added three prediction styles: Simple, Advanced, Pro Video.
- Added Pro Video visual layers: glow strokes, pocket locks, ghost-ball ring, bank hints, and after-hit guides.
- Added optional Relay Bridge fallback: Broadcast Extension -> HTTPS relay -> PiP Preview.
- Added `ZGOverlayRelayServer/`, a tiny Node relay server for builds where App Group sharing fails.
- Made Direct ZG recorder mode default ON and surfaced it in the Screen Recording card.
- Added installed-extension diagnostics so the app can report whether the broadcast `.appex` is actually embedded.
- Added scene classification (`gameplay_table`, `partial_table_or_transition`, `lobby_menu`) and table confidence.
- Improved table detection using green cloth, 2:1 table geometry, and six-pocket validation.
- Added visible aim-guide detection so the first prediction line follows the in-game cue guide when visible.
- Simplified the floating preview toward the reference style: dark table, red pocket rings, white main line, colored bounce lines.
- Direct picker mode now defaults ON to target `Z G Overlay Record`; turn it OFF only to troubleshoot the full Apple chooser.
- Added optional direct extension mode for testing.
- Added microphone option toggle.
- Added app group diagnostics.
- Added broadcast lifecycle diagnostics: status, frame count, detected balls, line count, writer status, and writer error.
- Added Share Replay and Clear buttons for test runs.
- Added full GitHub/Codemagic upload and signing instructions.
- Improved instructions inside the app.

## Direct mode note

Direct ZG recorder mode is ON by default so the blue button targets `Z G Overlay Record`. If tapping does nothing after signing, turn Direct mode OFF in Status/Diagnostics to show Apple's full chooser and confirm whether the extension is installed.

## Launch-together note

The supported near-in-game workflow is ReplayKit broadcast + PiP. A separate normal iOS app cannot silently inject a private overlay into another app. Once the original Cocos2d-x source is recovered, the best final version is a native in-game HUD layer using the same prediction logic.

## Different solution added

If the local App Group bridge still fails after signing, use Relay Bridge. It avoids App Group and pasteboard communication by sending the latest state and preview frame through a small HTTPS server.
