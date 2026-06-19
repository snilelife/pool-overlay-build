# Z G Replay Overlay — Screen Recording V3

This version changes the old small blue broadcast square into a **WhatsApp-style screen recording / screen sharing start button**.

## What changed in V3

- Animated entry screen with private code `777`.
- Bubble-style ZG branding on the entry screen and header.
- Big full-width **START SCREEN RECORDING** button.
- Reworked the ReplayKit picker hit area so the full blue button opens Apple's broadcast UI.
- Added **Floating Preview** using Apple's Picture-in-Picture system.
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

## Floating Preview

The Floating Preview uses Apple's supported Picture-in-Picture path:

```text
AVPictureInPictureController + AVSampleBufferDisplayLayer
```

It can float like a small YouTube-style PiP window while you switch apps. It cannot become a private transparent, touch-through overlay on top of another app. It shows the latest scanned prediction output from the App Group JSON.

## iOS rule

iOS does not allow a normal app to silently start screen recording. The user must approve it through Apple's broadcast UI. This is why the button opens the system broadcast sheet.
