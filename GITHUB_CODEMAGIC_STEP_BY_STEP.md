# GitHub + Codemagic step-by-step

## 1. What to upload to GitHub

Unzip this package. Open the folder:

```text
ZGReplayVisualOverlay_SCREEN_RECORDING_V3_ROOT_UPLOAD_ONLY
```

Upload the files and folders **inside** that folder to the root of your GitHub repo.

Your GitHub root should look like this:

```text
codemagic.yaml
project.yml
README.md
DO_THIS_FIRST_SIMPLE.md
LIMITS_READ_FIRST.md
IMPROVEMENT_REPORT.md
GITHUB_CODEMAGIC_STEP_BY_STEP.md
ZGReplayVisualOverlay/
ZGReplayVisualOverlayBroadcast/
ZGOverlayRelayServer/
```

Do not upload the parent zip folder itself as a folder inside the repo. The files above must be at the repo root.

## 2. Important files

Main app UI:

```text
ZGReplayVisualOverlay/Sources/ContentView.swift
```

Blue ReplayKit recording button:

```text
ZGReplayVisualOverlay/Sources/BroadcastPickerView.swift
```

Floating Picture-in-Picture preview:

```text
ZGReplayVisualOverlay/Sources/PiPOverlayPreview.swift
```

Settings shared with the broadcast extension:

```text
ZGReplayVisualOverlay/Sources/OverlaySettings.swift
```

Screen-recording analyzer extension:

```text
ZGReplayVisualOverlayBroadcast/Sources/SampleHandler.swift
```

Optional relay fallback server:

```text
ZGOverlayRelayServer/
```

XcodeGen project config:

```text
project.yml
```

Codemagic unsigned IPA workflow:

```text
codemagic.yaml
```

## 3. Build in Codemagic

1. Push the repo to GitHub.
2. Open Codemagic.
3. Connect/select the GitHub repo.
4. Choose this workflow:

```text
Build Z G Replay Visual Overlay unsigned IPA
```

5. Start the build.
6. When it finishes, download the artifact:

```text
ZGReplayVisualOverlay-ScreenRecording-V3-unsigned.ipa
```

## 4. Sign the IPA

Your signer must sign both:

```text
Payload/ZGReplayVisualOverlay.app
Payload/ZGReplayVisualOverlay.app/PlugIns/ZGReplayVisualOverlayBroadcast.appex
```

The app and extension must keep the same App Group:

```text
group.com.snilelife.zgreplayvisualoverlay
```

If your Apple account/profile exposes Broadcast Upload capability, enable it for the broadcast extension profile. If the extension does not appear in Apple's broadcast sheet, or the broadcast stops after the countdown, check signing/entitlements first.

If Apple's broadcast sheet shows apps like Photos, ChatGPT, or Discord but does **not** show:

```text
Z G Overlay Record
```

then the app opened the iOS recording UI correctly, but iOS does not see your broadcast extension as installed. Check these in order:

1. In the app, open Broadcast Diagnostics.
2. `Embedded .appex in installed app` must say `YES`.
3. `Embedded extension display name` must say `Z G Overlay Record`.
4. `App Group available now` should say `YES`.
5. Your signer must sign the nested `.appex`, not only the main `.app`.

If `Embedded .appex` says `NO`, the signer stripped or failed to install:

```text
Payload/ZGReplayVisualOverlay.app/PlugIns/ZGReplayVisualOverlayBroadcast.appex
```

If `Embedded .appex` says `YES` but the Apple sheet still does not list it, the likely problem is extension signing/capabilities.

## 5. First app test

1. Install the signed IPA.
2. Open the app.
3. Enter private code:

```text
777
```

4. Tap:

```text
START SCREEN RECORDING
```

5. In Apple's sheet, choose:

```text
Z G Overlay Record
```

6. Tap Start Broadcast.
7. Switch to your own pool/test screen.
8. Return to the app and check Analyzer State.

The app now has three pages:

```text
Live   - recording, scanner start/hold, floating preview
Assist - scan route, prediction style, line/bounce/pocket settings
Status - analyzer state, signing diagnostics, iOS limits
```

You should see broadcast status, processed frames, detected balls, prediction line count, writer status, and replay availability.

For the floating preview to show the actual game screen, these must become true after broadcast starts:

```text
Broadcast Status: running
Frames Processed: increasing
Live Preview Frame: ready
```

If `Frames Processed` stays `0`, the broadcast extension is not receiving video samples.

If `Frames Processed` increases but `Live Preview Frame` stays `not available`, the extension is running but the app cannot read the shared preview frame. Check App Group signing.

If App Group signing keeps failing, use the Relay Bridge fallback in section 8.

The scanner now reports:

```text
Detected Scene
Table Confidence
```

Expected behavior:

- lobby/matchmaking/menu screens report `lobby_menu` or `partial_table_or_transition`
- real top-down gameplay table screens report `gameplay_table`
- prediction lines only appear on `gameplay_table`
- if the in-game white cue guide is visible, the first prediction follows that guide
- if the cue guide is not visible, the analyzer falls back to ball/pocket geometry

## 5A. Assist mode test matrix

Open the **Assist** page and test these in order:

```text
1. Auto Hybrid + Advanced
   Best default for normal use.

2. Guide Lock + Simple
   Fastest route when the white in-game aim guide is clearly visible.

3. Ball Geometry + Advanced
   Best route when the game guide is hidden or unreliable.

4. Corner Lock + Pro Video
   Best fallback for checking table/pocket lock and visual style.

5. Auto Hybrid + Pro Video
   Most complete look: glow lines, ghost-ball ring, pocket lock, bank hints.
```

Use **STOP / HOLD** when the prediction is correct. The preview keeps the last scan visible for the **Hold Scan Result** seconds, so you can move the floating window aside and read it.

PiP play/pause can also resume or hold the scanner while you are outside the app.

## 6. Floating preview test

The Floating Preview uses Apple's Picture-in-Picture system. It is a small floating video-style window, like YouTube PiP. It is not a private transparent overlay.

Test it like this:

1. Open the app and enter `777`.
2. Start the screen broadcast first.
3. Return to the app after frames have processed.
4. In Floating Preview, tap:

```text
START FLOATING PREVIEW
```

5. Switch to another app.
6. iOS should keep the PiP preview floating if the device, iOS version, and signing allow PiP.

The PiP preview reads:

```text
zg_overlay_state.json
```

from the App Group and renders the latest scanned table, prediction lines, detected balls, and pocket marker.

## 6A. Launch-together workflow

iOS does not support a normal app silently launching as a private overlay on top of another app. Use one of these safe routes:

```text
Route A - Manual:
Open Z G Replay Overlay, start broadcast, start floating preview, switch to the game.

Route B - Relay Bridge:
Deploy ZGOverlayRelayServer to a public HTTPS host.
Set relayBaseURL in both Swift files.
Rebuild the IPA.

Route C - Shortcut:
Create an iOS Shortcut:
1. Open App: Z G Replay Overlay
2. Wait 2 seconds
3. Open App: your game

Start the broadcast/PiP before the shortcut opens the game.

Route D - Native later:
When source code is recovered, add the same prediction HUD directly as a Cocos2d-x layer in your game.
```

## 8. Relay Bridge fallback

Use this when recording starts but the app/PiP still cannot receive frames because App Group is broken after signing.

1. Deploy:

```text
ZGOverlayRelayServer/
```

to a public HTTPS host such as Render, Railway, Fly.io, or a VPS.

2. Open:

```text
ZGReplayVisualOverlay/Sources/OverlaySettings.swift
ZGReplayVisualOverlayBroadcast/Sources/SampleHandler.swift
```

3. In both files, set the same URL:

```swift
static let relayBaseURL = "https://your-zg-relay-host"
```

4. Keep the same stream key in both:

```swift
static let relayStreamKey = "zg-default"
```

5. Commit, push, rebuild in Codemagic, sign, install.

6. In the app, open Status and check:

```text
Relay Bridge: ON
```

This changes the live data route to:

```text
Broadcast Extension -> HTTPS Relay -> PiP Preview
```

It does not depend on App Group entitlements.

## 7. What changed for PiP

Added:

```text
ZGReplayVisualOverlay/Sources/PiPOverlayPreview.swift
```

Updated:

```text
ZGReplayVisualOverlay/Sources/ContentView.swift
project.yml
README.md
```

`project.yml` now includes:

```text
UIBackgroundModes:
  - audio
```

That is required for Apple's PiP playback path.

## 8. Good next features

Recommended next upgrades for your own game build:

- screenshot calibration mode for exact table corners
- manual cue ball/object ball correction
- line style presets for premium users
- shot confidence indicator
- save/load per-device table calibration
- premium gating for Floating Preview, max bounces, and annotated replay export
- Cocos2d-x in-game native overlay when you recover the original source
