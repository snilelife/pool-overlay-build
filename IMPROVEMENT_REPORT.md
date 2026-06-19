# V3 improvement report

## Main request

Make the blue button act like a screen recording / screen sharing function, similar to WhatsApp screen sharing.

## Implemented

- Added animated **Created by ZG** entry screen with private code `777`.
- Added bubble-style ZG branding for a less plain visual design.
- Replaced small picker square with a full-width visible button.
- The visible button says **START SCREEN RECORDING**.
- The ReplayKit picker now has an explicit full-size SwiftUI frame and UIKit hit-test forwarding, so tapping anywhere on the blue button opens Apple's broadcast UI.
- Added Floating Preview using `AVPictureInPictureController` and `AVSampleBufferDisplayLayer`.
- Default picker mode no longer hard-forces the extension bundle ID. This is more reliable after phone signing.
- Added optional direct extension mode for testing.
- Added microphone option toggle.
- Added app group diagnostics.
- Added broadcast lifecycle diagnostics: status, frame count, detected balls, line count, writer status, and writer error.
- Added Share Replay and Clear buttons for test runs.
- Added full GitHub/Codemagic upload and signing instructions.
- Improved instructions inside the app.

## Reason for default non-direct mode

Phone signing tools sometimes change bundle identifiers. If the app hardcodes the extension id and the signer changes it, the picker may do nothing. V3 defaults to Apple's chooser so the user can select the installed extension manually.
