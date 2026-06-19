# Z G Replay Overlay — Screen Recording V3

This version changes the old small blue broadcast square into a **WhatsApp-style screen recording / screen sharing start button**.

## What changed in V3

- Animated entry screen with private code `777`.
- Three-page app layout: **Live**, **Assist**, and **Status**.
- Live feature tiles show Scanner, Scan Route, Prediction Style, and Hold Window.
- Bubble-style ZG branding on the entry screen and header.
- Big full-width **START SCREEN RECORDING** button.
- Reworked the ReplayKit picker hit area so the full blue button opens Apple's broadcast UI.
- Added **Floating Preview** using Apple's Picture-in-Picture system.
- Added **START SCANNER** and **STOP / HOLD** controls.
- Added hold-last-scan behavior so a good prediction stays visible while moving the floating window.
- Added PiP play/pause control support for scanner resume/hold.
- Added scan routes: **Auto Hybrid**, **Guide Lock**, **Ball Geometry**, and **Corner Lock**.
- Added prediction styles: **Simple**, **Advanced**, and **Pro Video**.
- Added scene classification so lobby/menu frames do not get prediction lines.
- Improved gameplay-table detection using green cloth, six-pocket geometry, and table confidence.
- Added stable table locking to reduce line jitter.
- Added visible aim-guide detection for simpler, cleaner prediction lines.
- Added live annotated preview frames from the broadcast extension so PiP can show the captured game screen, not only synthetic JSON lines.
- Uses Apple's ReplayKit broadcast sheet, the same user-approved style used by screen sharing apps.
- Default mode opens Apple's normal broadcast chooser, which is safer after phone signing.
- Added optional microphone button toggle.
- Added direct-extension mode as a diagnostic option only.
- Added clearer steps in the app UI.
- Improved diagnostics for app group, broadcast lifecycle, processed frames, detected balls, writer status, and replay export.
- Added Share Replay and Clear buttons for test runs.
- Keeps the visual analyzer, table scanner, prediction lines, ghost ball, detected balls, and annotated replay writer.

## Full setup guide

Read:

```text
GITHUB_CODEMAGIC_STEP_BY_STEP.md
```

## Build

Upload these files to the root of your GitHub repository, then build with Codemagic.

Expected GitHub root files/folders:

```text
codemagic.yaml
project.yml
ZGReplayVisualOverlay
ZGReplayVisualOverlayBroadcast
README.md
DO_THIS_FIRST_SIMPLE.md
LIMITS_READ_FIRST.md
GITHUB_CODEMAGIC_STEP_BY_STEP.md
```

Codemagic workflow:

```text
Build Z G Replay Visual Overlay unsigned IPA
```

After build succeeds, download:

```text
ZGReplayVisualOverlay-ScreenRecording-V3-unsigned.ipa
```

Then sign it on your phone.

## Login

The app opens with:

```text
Created by ZG
Enter private code
```

Use:

```text
777
```

## Very important for phone signing

Your phone signer must sign the main app **and** the nested broadcast extension:

```text
Payload/ZGReplayVisualOverlay.app/PlugIns/ZGReplayVisualOverlayBroadcast.appex
```

If the extension is not signed/embedded correctly, the START SCREEN RECORDING button may open the Apple sheet but `Z G Overlay Record` may not appear.

For iOS 26.5.1 and newer builds, keep this supported ReplayKit path:

```text
RPSystemBroadcastPickerView -> RPBroadcastSampleHandler
```

If the Apple broadcast sheet opens but the broadcast immediately stops after the countdown, check signing first:

- the main app must be signed
- `Payload/ZGReplayVisualOverlay.app/PlugIns/ZGReplayVisualOverlayBroadcast.appex` must also be signed
- both targets must preserve the same App Group entitlement
- if your Apple developer account/profile shows a Broadcast Upload capability, enable it for the broadcast extension profile

If the sheet shows Photos, ChatGPT, or Discord but not `Z G Overlay Record`, the iOS recording UI is opening correctly, but the broadcast extension is not installed/registered. In the app, check Broadcast Diagnostics:

- `Embedded .appex in installed app` must be `YES`
- `Embedded extension display name` must be `Z G Overlay Record`
- `App Group available now` should be `YES`
- if Direct mode is ON and the signer changed bundle IDs, turn Direct mode OFF and check the chooser

## Floating Preview

The Floating Preview uses Apple's supported Picture-in-Picture path:

```text
AVPictureInPictureController + AVSampleBufferDisplayLayer
```

It can float like a small YouTube-style PiP window while you switch apps. It cannot become a private transparent, touch-through overlay on top of another app. It shows the latest scanned prediction output from the App Group JSON.

## Assist Modes

Open the **Assist** page and test these combinations:

```text
Scan Route:
1. Auto Hybrid - tries guide line, then ball geometry, then corner/pocket fallback
2. Guide Lock - fastest when the visible in-game guide line is on screen
3. Ball Geometry - uses detected cue/object balls and ghost-ball math
4. Corner Lock - steady fallback using detected table and pocket geometry

Prediction Style:
1. Simple - clean main aim line, fastest
2. Advanced - ghost ball, pocket line, bounces, detected balls
3. Pro Video - glow lines, pocket locks, bank hints, after-hit guides, stronger markers
```

For fastest testing, start with:

```text
Fast Scan Mode: ON
Scan Route: Auto Hybrid
Prediction Style: Advanced
Hold Last Scan: ON
Hold Scan Result: 8s
```

When a useful prediction appears, use **STOP / HOLD** or the PiP pause control. The last scanned result remains visible for the hold window.

## Launch-together options

iOS does not allow a separate normal app to inject a private overlay into another app or silently draw above it. The supported options are:

```text
Route A - Current app:
ReplayKit broadcast + PiP floating preview.

Route B - Shortcut flow:
Create an iOS Shortcut that opens Z G Replay Overlay first, then opens your game after you start PiP.

Route C - Native source-code integration:
When you recover the Cocos2d-x source, add the prediction HUD as a Cocos2d-x layer inside the game itself.
```

Route C is the only way to make it behave exactly like an in-game overlay without relying on PiP.

## iOS rule

iOS does not allow a normal app to silently start screen recording. The user must approve it through Apple's broadcast UI. This is why the button opens the system broadcast sheet.
