# Do this first — simple

1. Delete the old files from your GitHub repo.
2. Unzip this V3 package.
3. Upload everything **inside** the unzipped folder to GitHub.
4. Make sure GitHub root shows:

```text
codemagic.yaml
project.yml
ZGReplayVisualOverlay
ZGReplayVisualOverlayBroadcast
README.md
GITHUB_CODEMAGIC_STEP_BY_STEP.md
```

5. Go to Codemagic.
6. Start build:

```text
Build Z G Replay Visual Overlay unsigned IPA
```

7. Download the IPA from Artifacts.
8. Sign it on your phone.

Inside the app, tap:

```text
START SCREEN RECORDING
```

Then choose:

```text
Z G Overlay Record
```

Then switch to your pool/test screen.

The private entry code is:

```text
777
```

After a test broadcast, return to the app and check Analyzer State. It should show status, frame count, detected balls, writer status, and a Share Replay button if an annotated replay was created.

For the small floating preview:

1. Start the broadcast first.
2. Return to the app after frames process.
3. Tap `START FLOATING PREVIEW`.
4. Switch to another app and iOS should keep the PiP preview floating if PiP is available.
