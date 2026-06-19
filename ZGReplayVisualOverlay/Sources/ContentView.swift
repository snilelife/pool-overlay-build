import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var store = OverlaySettingsStore()
    @StateObject private var pipPreview = PiPOverlayPreviewController()
    @State private var latestState = "No analyzer state yet."
    @State private var hasAccess = false
    @State private var annotatedReplayURL: URL?

    var body: some View {
        ZStack {
            appBackground

            if hasAccess {
                mainContent
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                AccessGateView {
                    withAnimation(.spring(response: 0.52, dampingFraction: 0.82)) {
                        hasAccess = true
                    }
                }
                .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
        }
        .preferredColorScheme(.dark)
        .animation(.spring(response: 0.52, dampingFraction: 0.82), value: hasAccess)
        .onAppear {
            store.save()
            refreshLatestState()
        }
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
            guard hasAccess else { return }
            refreshLatestState()
        }
    }

    private var appBackground: some View {
        LinearGradient(
            colors: [Color(red: 0.035, green: 0.045, blue: 0.075), Color(red: 0.0, green: 0.075, blue: 0.095)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                screenRecordingCard
                floatingPreviewCard
                controlsCard
                analyzerCard
                diagnosticsCard
                limitCard
            }
            .padding(18)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color(red: 0.0, green: 0.55, blue: 0.88).opacity(0.24))
                BubbleText("ZG", size: 22)
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 4) {
                BubbleText("Z G Replay Overlay", size: 27)
                Text("WhatsApp-style screen recording + frame analyzer")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.66))
            }

            Spacer()
        }
    }

    private var screenRecordingCard: some View {
        panel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "record.circle.fill")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(Color(red: 0.05, green: 0.62, blue: 1.0))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Screen Recording")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("Same flow as screen sharing: start broadcast, switch app, stop when done.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.66))
                    }
                    Spacer()
                }

                screenRecordStartButton

                VStack(alignment: .leading, spacing: 8) {
                    stepLine("1", "Tap START SCREEN RECORDING")
                    stepLine("2", "Choose Z G Overlay Record in Apple’s broadcast sheet")
                    stepLine("3", "Tap Start Broadcast, then switch to your pool screen")
                    stepLine("4", "Stop from the red status bar / Dynamic Island / Control Center")
                }
                .padding(12)
                .background(Color.white.opacity(0.055))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Toggle("Show microphone option", isOn: binding(\.showMicrophoneButton))
                    .tint(Color(red: 0.05, green: 0.62, blue: 1.0))
                    .font(.system(size: 14, weight: .semibold))
            }
        }
    }

    private var screenRecordStartButton: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.03, green: 0.58, blue: 1.0), Color(red: 0.00, green: 0.35, blue: 0.92)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color.blue.opacity(0.28), radius: 16, x: 0, y: 8)

            HStack(spacing: 12) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 22, weight: .heavy))
                Text("START SCREEN RECORDING")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)

            // The invisible ReplayKit picker sits on top so the whole blue button opens Apple's broadcast UI.
            BroadcastPickerButton(
                preferredExtension: store.settings.directZGExtensionMode ? ZGShared.extensionBundleID : nil,
                showsMicrophoneButton: store.settings.showMicrophoneButton
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity)
        .frame(height: 68)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityLabel("Start screen recording broadcast")
    }

    private func stepLine(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text(number)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(.black)
                .frame(width: 21, height: 21)
                .background(Color(red: 0.12, green: 0.85, blue: 1.0))
                .clipShape(Circle())
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.80))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var floatingPreviewCard: some View {
        panel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "pip.enter")
                        .font(.system(size: 31, weight: .bold))
                        .foregroundStyle(Color(red: 0.18, green: 0.90, blue: 0.74))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Floating Preview")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("Small PiP window for the latest scanned prediction output.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.66))
                    }

                    Spacer()
                }

                PiPOverlayPreviewSurface(controller: pipPreview)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 280)
                    .frame(maxWidth: .infinity)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )

                HStack(spacing: 10) {
                    Button {
                        pipPreview.toggle()
                    } label: {
                        Label(
                            pipPreview.isActive ? "STOP FLOATING PREVIEW" : "START FLOATING PREVIEW",
                            systemImage: pipPreview.isActive ? "pip.exit" : "pip.enter"
                        )
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.04, green: 0.62, blue: 0.82))
                    .disabled(!pipPreview.isSupported)

                    Button {
                        pipPreview.renderNow()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 17, weight: .heavy))
                            .frame(width: 48, height: 48)
                    }
                    .buttonStyle(.bordered)
                }

                Text(pipPreview.statusText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.68))
            }
        }
    }

    private var controlsCard: some View {
        panel {
            VStack(spacing: 12) {
                sectionTitle("Prediction Controls")
                controlToggle("Enable Prediction Lines", \.predictionEnabled)
                controlToggle("Keep Line", \.keepLine)
                controlToggle("Manual Choose Pocket", \.manualPocket)
                controlToggle("Side Lines", \.showSideLines)
                controlToggle("Record Annotated Video", \.recordAnnotatedVideo)
                controlToggle("Show Detected Balls", \.showDetectedBalls)
                controlToggle("Show Ghost Ball", \.showGhostBall)

                Divider().overlay(Color.white.opacity(0.12))

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Line Length")
                        Spacer()
                        Text("\(Int(store.settings.lineLength * 100))%")
                            .foregroundStyle(Color(red: 0.15, green: 0.84, blue: 1.0))
                    }
                    Slider(value: binding(\.lineLength), in: 0.25...1.0)
                }

                Stepper(value: binding(\.maxBounces), in: 0...6) {
                    HStack {
                        Text("Max Bounces")
                        Spacer()
                        Text("\(store.settings.maxBounces)")
                            .foregroundStyle(Color(red: 0.15, green: 0.84, blue: 1.0))
                    }
                }

                Picker("Manual Pocket", selection: binding(\.selectedPocket)) {
                    Text("Top Left").tag(0)
                    Text("Top Middle").tag(1)
                    Text("Top Right").tag(2)
                    Text("Bottom Left").tag(3)
                    Text("Bottom Middle").tag(4)
                    Text("Bottom Right").tag(5)
                }
                .pickerStyle(.menu)
            }
            .font(.system(size: 15, weight: .semibold))
        }
    }

    private var analyzerCard: some View {
        panel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    sectionTitle("Analyzer State")
                    Spacer()
                    Button {
                        refreshLatestState()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }

                Text(latestState)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.black.opacity(0.34))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                HStack(spacing: 10) {
                    if let annotatedReplayURL {
                        ShareLink(item: annotatedReplayURL) {
                            Label("Share Replay", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Button(role: .destructive) {
                        clearAnalyzerState()
                    } label: {
                        Label("Clear", systemImage: "trash")
                            .frame(maxWidth: annotatedReplayURL == nil ? .infinity : nil)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var diagnosticsCard: some View {
        panel {
            VStack(alignment: .leading, spacing: 9) {
                sectionTitle("Broadcast Diagnostics")
                labelValue("Extension shown in Apple sheet", "Z G Overlay Record")
                labelValue("Expected Extension ID", ZGShared.extensionBundleID)
                labelValue("Shared App Group", ZGShared.appGroupID)
                labelValue("App Group available now", ZGShared.appGroupReady ? "YES" : "NO / signer may need App Group entitlement")
                labelValue("ReplayKit API path", "RPSystemBroadcastPickerView + RPBroadcastSampleHandler")

                Toggle("Direct ZG extension mode", isOn: binding(\.directZGExtensionMode))
                    .tint(Color(red: 0.05, green: 0.62, blue: 1.0))
                    .font(.system(size: 14, weight: .semibold))

                Text("Leave Direct mode OFF if you sign on phone. OFF opens Apple’s chooser, which is more reliable when the signer changes bundle IDs. If the extension does not appear, the .appex was not signed/embedded correctly.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.66))
            }
        }
    }

    private var limitCard: some View {
        panel {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("iOS Limit")
                Text("iOS allows this app to receive screen frames through ReplayKit after the user starts the broadcast. It cannot silently start recording or draw a live overlay on top of another app without the system broadcast flow.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 18, weight: .bold, design: .rounded))
    }

    private func labelValue(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.55))
            Text(value).font(.system(.footnote, design: .monospaced)).foregroundStyle(.white.opacity(0.88))
        }
    }

    private func panel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(Color.black.opacity(0.56))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
    }

    private func controlToggle(_ title: String, _ keyPath: WritableKeyPath<OverlaySettings, Bool>) -> some View {
        Toggle(title, isOn: binding(keyPath))
            .tint(Color(red: 0.02, green: 0.48, blue: 0.95))
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<OverlaySettings, Value>) -> Binding<Value> {
        Binding(
            get: { store.settings[keyPath: keyPath] },
            set: { newValue in
                store.settings[keyPath: keyPath] = newValue
                store.save()
            }
        )
    }

    private func refreshLatestState() {
        let url = ZGShared.sharedContainerURL().appendingPathComponent("zg_overlay_state.json")
        let replayURL = ZGShared.sharedContainerURL().appendingPathComponent("ZGAnnotatedReplay.mov")
        annotatedReplayURL = FileManager.default.fileExists(atPath: replayURL.path) ? replayURL : nil

        let defaults = ZGShared.sharedDefaults()
        let timestamp = defaults.double(forKey: "broadcastLastEvent")
        let diagnostics = [
            "App Group Ready: \(ZGShared.appGroupReady ? "YES" : "NO")",
            "Broadcast Status: \(defaults.string(forKey: "broadcastStatus") ?? "not started")",
            "Frames Processed: \(defaults.integer(forKey: "broadcastFrameCount"))",
            "Detected Balls: \(defaults.integer(forKey: "broadcastDetectedBalls"))",
            "Prediction Lines: \(defaults.integer(forKey: "broadcastLineCount"))",
            "Writer Status: \(defaults.string(forKey: "broadcastWriterStatus") ?? "not recording")",
            "Replay File: \(annotatedReplayURL == nil ? "not available" : "ready to share")",
            "Last Event: \(format(timestamp: timestamp))"
        ].joined(separator: "\n")

        let writerError = defaults.string(forKey: "broadcastWriterError")
        let errorText = writerError.map { "\n\nWriter Error:\n\($0)" } ?? ""

        if let text = try? String(contentsOf: url, encoding: .utf8) {
            latestState = diagnostics + errorText + "\n\nLatest Overlay JSON:\n" + text
        } else {
            latestState = diagnostics + errorText + "\n\nNo analyzer state yet.\nStart a broadcast, switch to the game/testing screen, stop it, then refresh."
        }
    }

    private func clearAnalyzerState() {
        let container = ZGShared.sharedContainerURL()
        for filename in ["zg_overlay_state.json", "ZGAnnotatedReplay.mov"] {
            try? FileManager.default.removeItem(at: container.appendingPathComponent(filename))
        }

        let defaults = ZGShared.sharedDefaults()
        for key in [
            "broadcastStatus",
            "broadcastFrameCount",
            "broadcastDetectedBalls",
            "broadcastLineCount",
            "broadcastWriterStatus",
            "broadcastWriterError",
            "broadcastReplayAvailable",
            "broadcastLastNote",
            "broadcastLastEvent"
        ] {
            defaults.removeObject(forKey: key)
        }
        defaults.synchronize()
        refreshLatestState()
    }

    private func format(timestamp: Double) -> String {
        guard timestamp > 0 else { return "never" }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }
}

private struct AccessGateView: View {
    var onUnlock: () -> Void

    @State private var code = ""
    @State private var showError = false
    @State private var animateIn = false
    @FocusState private var codeFieldFocused: Bool

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 28)

            ZStack {
                Circle()
                    .fill(Color(red: 0.05, green: 0.62, blue: 1.0).opacity(animateIn ? 0.30 : 0.12))
                    .frame(width: 142, height: 142)
                    .blur(radius: animateIn ? 16 : 4)

                Circle()
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                    .background(Circle().fill(Color.black.opacity(0.48)))
                    .frame(width: 118, height: 118)

                BubbleText("ZG", size: 45)
            }
            .scaleEffect(animateIn ? 1.0 : 0.88)
            .shadow(color: Color(red: 0.05, green: 0.62, blue: 1.0).opacity(animateIn ? 0.44 : 0.12), radius: 28, x: 0, y: 10)

            VStack(spacing: 7) {
                BubbleText("Created by ZG", size: 32)

                Text("Enter private code")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.68))
            }
            .offset(y: animateIn ? 0 : 10)
            .opacity(animateIn ? 1 : 0)

            VStack(spacing: 12) {
                SecureField("Private code", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .focused($codeFieldFocused)
                    .padding(.horizontal, 18)
                    .frame(height: 58)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(showError ? Color.red.opacity(0.86) : Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .onChange(of: code) { newValue in
                        let filtered = String(newValue.filter(\.isNumber).prefix(6))
                        if filtered != newValue { code = filtered }
                        if showError { showError = false }
                    }

                if showError {
                    Text("Wrong code")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.red.opacity(0.92))
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Button {
                    submit()
                } label: {
                    Label("Enter", systemImage: "lock.open.fill")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.03, green: 0.58, blue: 1.0))
            }
            .frame(maxWidth: 360)
            .padding(.horizontal, 24)
            .offset(y: animateIn ? 0 : 18)
            .opacity(animateIn ? 1 : 0)

            Spacer(minLength: 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            codeFieldFocused = true
            withAnimation(.spring(response: 0.7, dampingFraction: 0.82)) {
                animateIn = true
            }
        }
    }

    private func submit() {
        guard code.trimmingCharacters(in: .whitespacesAndNewlines) == "777" else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            withAnimation(.spring(response: 0.28, dampingFraction: 0.62)) {
                showError = true
            }
            return
        }

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onUnlock()
    }
}

private struct BubbleText: View {
    private let text: String
    private let size: CGFloat

    init(_ text: String, size: CGFloat) {
        self.text = text
        self.size = size
    }

    var body: some View {
        ZStack {
            ForEach(0..<outlineOffsets.count, id: \.self) { index in
                Text(text)
                    .font(.system(size: size, weight: .black, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.54))
                    .offset(outlineOffsets[index])
            }

            Text(text)
                .font(.system(size: size, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color.white,
                            Color(red: 0.63, green: 0.95, blue: 1.0),
                            Color(red: 0.08, green: 0.58, blue: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color.white.opacity(0.34), radius: 1.6, x: 0, y: 1)
                .shadow(color: Color(red: 0.05, green: 0.62, blue: 1.0).opacity(0.45), radius: 7, x: 0, y: 3)
        }
        .fixedSize(horizontal: true, vertical: true)
    }

    private var outlineOffsets: [CGSize] {
        [
            CGSize(width: -1.6, height: 0),
            CGSize(width: 1.6, height: 0),
            CGSize(width: 0, height: -1.6),
            CGSize(width: 0, height: 1.8)
        ]
    }
}
