# Limits read first

This app uses ReplayKit Broadcast Upload Extension.

It can:

- open Apple's screen broadcast sheet
- receive broadcast video frames inside the extension
- analyze the frames visually
- write analyzer state JSON
- create an annotated replay video with prediction lines
- show broadcast diagnostics after you return to the app
- show a small floating Picture-in-Picture preview using Apple's PiP window

It cannot:

- silently start screen recording without the Apple sheet
- draw live full-screen lines on top of another app like Android overlays
- create a transparent touch-through overlay outside the app
- bypass another app's protections

For a WhatsApp-like flow, the correct iOS approach is:

```text
START SCREEN RECORDING button
→ Apple Start Broadcast sheet
→ user chooses Z G Overlay Record
→ extension receives frames
→ analyzer writes prediction/replay output
```

If the extension does not appear in the Apple sheet, or if the broadcast stops after the countdown, that is usually signing/entitlement/embedding rather than button code. The main app and broadcast extension must both be signed, embedded, and allowed to share the same App Group.

The Floating Preview uses:

```text
AVPictureInPictureController + AVSampleBufferDisplayLayer
```

That is a real Apple-supported floating window, similar to YouTube PiP, but the system controls its shape, placement, and behavior.
