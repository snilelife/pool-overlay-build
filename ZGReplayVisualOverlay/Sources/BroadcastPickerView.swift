import ReplayKit
import SwiftUI
import UIKit

/// Full-size ReplayKit broadcast picker.
/// This gives the same kind of user-approved screen broadcast flow used by screen-sharing apps:
/// tap our visible button -> iOS opens the Start Broadcast sheet -> frames go to the Broadcast Upload Extension.
/// iOS does not allow silent/background screen recording start, so this system picker must remain in the app.
struct BroadcastPickerButton: UIViewRepresentable {
    /// Pass nil to show Apple's normal broadcast-extension chooser. This is safest after phone signing,
    /// because some signers change bundle identifiers. Pass the exact extension bundle id only for direct mode.
    var preferredExtension: String?
    var showsMicrophoneButton: Bool = false

    func makeUIView(context: Context) -> BroadcastPickerContainerView {
        let view = BroadcastPickerContainerView()
        view.preferredExtension = preferredExtension
        view.showsMicrophoneButton = showsMicrophoneButton
        return view
    }

    func updateUIView(_ uiView: BroadcastPickerContainerView, context: Context) {
        uiView.preferredExtension = preferredExtension
        uiView.showsMicrophoneButton = showsMicrophoneButton
    }
}

final class BroadcastPickerContainerView: UIView {
    private let picker = RPSystemBroadcastPickerView(frame: .zero)

    var preferredExtension: String? {
        didSet {
            picker.preferredExtension = preferredExtension?.isEmpty == true ? nil : preferredExtension
            configureInternalButton()
        }
    }

    var showsMicrophoneButton: Bool = false {
        didSet {
            picker.showsMicrophoneButton = showsMicrophoneButton
            configureInternalButton()
        }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: 280, height: 68)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        isUserInteractionEnabled = true
        isOpaque = false
        clipsToBounds = false
        backgroundColor = .clear
        picker.isUserInteractionEnabled = true
        picker.isOpaque = false
        picker.backgroundColor = .clear
        picker.showsMicrophoneButton = false
        picker.translatesAutoresizingMaskIntoConstraints = false
        addSubview(picker)
        NSLayoutConstraint.activate([
            picker.leadingAnchor.constraint(equalTo: leadingAnchor),
            picker.trailingAnchor.constraint(equalTo: trailingAnchor),
            picker.topAnchor.constraint(equalTo: topAnchor),
            picker.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        configureInternalButton()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        configureInternalButton()
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.contains(point)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard bounds.contains(point) else { return nil }
        configureInternalButton()

        let pickerPoint = convert(point, to: picker)
        for subview in picker.subviews where subview is UIButton {
            return subview
        }
        return picker.hitTest(pickerPoint, with: event) ?? picker
    }

    private func configureInternalButton() {
        for subview in picker.subviews {
            subview.frame = picker.bounds
            subview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            subview.isUserInteractionEnabled = true

            if let button = subview as? UIButton {
                button.setImage(nil, for: .normal)
                button.setTitle("", for: .normal)
                button.backgroundColor = .clear
                button.tintColor = .clear
                button.adjustsImageWhenHighlighted = false
                button.accessibilityLabel = "Start Z G Overlay screen recording broadcast"
                button.contentEdgeInsets = UIEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
            }
        }
    }
}
