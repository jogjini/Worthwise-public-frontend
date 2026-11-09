import AVFoundation
import SwiftUI
import UIKit

/// Custom AVFoundation capture screen.
///
/// Replaces the previous `UIImagePickerController` implementation. That API gives no
/// way to learn which region of the sensor its preview was showing, so any crop had
/// to be guessed — which is why captures always looked shifted relative to the guide
/// box. Here we own the preview layer, so the guide box and the crop are derived from
/// the *same* geometry and cannot disagree.
struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    /// "Choose from library" when the camera can't start (C5). The host opens
    /// the picker once this cover has closed.
    var onChooseLibrary: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    init(image: Binding<UIImage?>, onChooseLibrary: (() -> Void)? = nil) {
        _image = image
        self.onChooseLibrary = onChooseLibrary
    }

    func makeUIViewController(context: Context) -> ScanCameraViewController {
        let controller = ScanCameraViewController()
        controller.onCapture = { captured in
            image = captured
            dismiss()
        }
        controller.onCancel = { dismiss() }
        controller.onChooseLibrary = {
            onChooseLibrary?()
            dismiss()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: ScanCameraViewController, context: Context) {}
}

// MARK: - Capture controller

/// Camera controls (05 §2.44, 06 M1–M3, §4.8): 72 pt shutter (ring + disc),
/// press feedback, a one-dip preview blink and the shutter haptic at capture,
/// a Dynamic Type hint on a scrim, Cancel, and a torch with an On/Off value.
/// When the session can't start, the shutter and torch are hidden and the
/// screen offers "Choose from library" instead (C5).
final class ScanCameraViewController: UIViewController {

    var onCapture: ((UIImage) -> Void)?
    var onCancel: (() -> Void)?
    var onChooseLibrary: (() -> Void)?

    /// Guide box width as a fraction of the preview width.
    private static let guideWidthRatio: CGFloat = 0.84
    /// Height of the bottom controls strip. The guide box centres in the space above it.
    private static let controlsHeight: CGFloat = 148
    private static let shutterSize: CGFloat = 72
    private static let shutterDiscSize: CGFloat = 56
    private static let torchSize: CGFloat = 44
    /// Text on the white "Choose from library" button and the lit torch glyph:
    /// the light `text` token, fixed (the camera is dark in both modes).
    private static let inkColor = UIColor(hex: WW.palette.text.light)

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "collectible.camera.session")
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var isConfigured = false
    private var pendingCrop: (guide: CGRect, layerSize: CGSize)?
    private var isTorchOn = false

    private let overlayView = ScanGuideOverlayView()
    private let blinkView = UIView()
    private let shutterButton = UIButton(type: .custom)
    private let shutterDisc = UIView()
    private let cancelButton = UIButton(type: .system)
    private let torchButton = UIButton(type: .custom)
    private let hintContainer = UIView()
    private let hintLabel = UILabel()
    private let unavailableStack = UIStackView()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.ww(WW.palette.photoBackdrop)

        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        overlayView.isUserInteractionEnabled = false
        overlayView.backgroundColor = .clear
        view.addSubview(overlayView)

        blinkView.backgroundColor = .black
        blinkView.alpha = 0
        blinkView.isUserInteractionEnabled = false
        view.addSubview(blinkView)

        setUpControls()
        setUpUnavailable()

        sessionQueue.async { [weak self] in self?.configureSession() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sessionQueue.async { [weak self] in
            guard let self, self.isConfigured, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Haptics.prepareShutter()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        setTorch(on: false)
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
        overlayView.frame = view.bounds
        blinkView.frame = view.bounds
        overlayView.guideRect = guideRect(in: view.bounds)
    }

    override var prefersStatusBarHidden: Bool { true }

    // MARK: - Geometry (single source of truth)

    /// The guide box in preview-layer coordinates. Both the drawn overlay and the crop
    /// applied to the captured photo come from this one function, so they cannot drift.
    private func guideRect(in bounds: CGRect) -> CGRect {
        let availableHeight = max(0, bounds.height - Self.controlsHeight)
        let side = min(bounds.width * Self.guideWidthRatio, availableHeight * 0.9)
        return CGRect(
            x: (bounds.width - side) / 2,
            y: (availableHeight - side) / 2,
            width: side,
            height: side
        )
    }

    /// Maps a rect in preview-layer coordinates to pixel coordinates in the captured
    /// image, accounting for `.resizeAspectFill` (the preview shows a centre crop of
    /// the full sensor frame).
    ///
    /// Pure and static so the arithmetic is unit-testable.
    static func imageCropRect(
        guideRect: CGRect,
        layerSize: CGSize,
        imagePixelSize: CGSize
    ) -> CGRect {
        guard layerSize.width > 0, layerSize.height > 0,
              imagePixelSize.width > 0, imagePixelSize.height > 0 else { return .zero }

        // Aspect fill: scale the image up until it covers the layer on both axes.
        let scale = max(layerSize.width / imagePixelSize.width,
                        layerSize.height / imagePixelSize.height)

        // How much of the scaled image falls outside the layer, per side.
        let overflowX = (imagePixelSize.width * scale - layerSize.width) / 2
        let overflowY = (imagePixelSize.height * scale - layerSize.height) / 2

        let rect = CGRect(
            x: (guideRect.minX + overflowX) / scale,
            y: (guideRect.minY + overflowY) / scale,
            width: guideRect.width / scale,
            height: guideRect.height / scale
        )

        // Never hand CGImage.cropping a rect that leaves the image.
        return rect.intersection(CGRect(origin: .zero, size: imagePixelSize)).integral
    }

    // MARK: - Session

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        defer {
            session.commitConfiguration()
            if isConfigured, !session.isRunning {
                session.startRunning()
            }
        }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            DispatchQueue.main.async { [weak self] in self?.showUnavailable() }
            return
        }
        session.addInput(input)

        guard session.canAddOutput(photoOutput) else {
            DispatchQueue.main.async { [weak self] in self?.showUnavailable() }
            return
        }
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .balanced

        isConfigured = true
    }

    /// C5 (06 M3): hide the shutter and torch — a live-looking shutter that
    /// does nothing is worse than none — and offer the library.
    private func showUnavailable() {
        shutterButton.isEnabled = false
        unavailableStack.isHidden = false
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut], animations: {
            self.shutterButton.alpha = 0
            self.torchButton.alpha = 0
            self.hintContainer.alpha = 0
            self.overlayView.alpha = 0
            self.unavailableStack.alpha = 1
        }, completion: { _ in
            self.shutterButton.isHidden = true
            self.torchButton.isHidden = true
            self.hintContainer.isHidden = true
        })
        UIAccessibility.post(notification: .screenChanged, argument: unavailableStack)
    }

    // MARK: - Controls

    private func setUpControls() {
        // Hint: "Fit one item inside the frame" on a scrim, Dynamic Type.
        hintContainer.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        hintContainer.layer.cornerRadius = 10
        hintContainer.layer.cornerCurve = .continuous
        hintContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hintContainer)

        hintLabel.text = "Fit one item inside the frame"
        hintLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: UIFont.systemFont(ofSize: 15, weight: .semibold))
        hintLabel.adjustsFontForContentSizeCategory = true
        hintLabel.textColor = .white
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 0
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintContainer.addSubview(hintLabel)

        // Shutter: 4 pt white ring, 4 pt gap, 56 pt white disc.
        shutterButton.backgroundColor = .clear
        shutterButton.layer.cornerRadius = Self.shutterSize / 2
        shutterButton.layer.borderWidth = 4
        shutterButton.layer.borderColor = UIColor.white.cgColor
        shutterButton.accessibilityLabel = "Take photo"
        shutterButton.addTarget(self, action: #selector(shutterDown), for: .touchDown)
        shutterButton.addTarget(self, action: #selector(shutterReleased), for: [.touchUpOutside, .touchCancel])
        shutterButton.addTarget(self, action: #selector(capture), for: .touchUpInside)
        shutterButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(shutterButton)

        shutterDisc.backgroundColor = .white
        shutterDisc.layer.cornerRadius = Self.shutterDiscSize / 2
        shutterDisc.isUserInteractionEnabled = false
        shutterDisc.translatesAutoresizingMaskIntoConstraints = false
        shutterButton.addSubview(shutterDisc)

        // Cancel: body Semibold, white, 44 × 44 minimum.
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.titleLabel?.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: UIFont.systemFont(ofSize: 17, weight: .semibold))
        cancelButton.titleLabel?.adjustsFontForContentSizeCategory = true
        cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cancelButton)

        // Torch: 44 pt circle; hidden on devices without one.
        torchButton.layer.cornerRadius = Self.torchSize / 2
        torchButton.accessibilityLabel = "Flashlight"
        torchButton.addTarget(self, action: #selector(toggleTorch), for: .touchUpInside)
        torchButton.translatesAutoresizingMaskIntoConstraints = false
        torchButton.isHidden = !Self.deviceHasTorch
        view.addSubview(torchButton)
        updateTorchAppearance()

        NSLayoutConstraint.activate([
            shutterButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutterButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            shutterButton.widthAnchor.constraint(equalToConstant: Self.shutterSize),
            shutterButton.heightAnchor.constraint(equalToConstant: Self.shutterSize),

            shutterDisc.centerXAnchor.constraint(equalTo: shutterButton.centerXAnchor),
            shutterDisc.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor),
            shutterDisc.widthAnchor.constraint(equalToConstant: Self.shutterDiscSize),
            shutterDisc.heightAnchor.constraint(equalToConstant: Self.shutterDiscSize),

            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            cancelButton.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor),
            cancelButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            cancelButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            cancelButton.trailingAnchor.constraint(lessThanOrEqualTo: shutterButton.leadingAnchor, constant: -8),

            torchButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            torchButton.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor),
            torchButton.widthAnchor.constraint(equalToConstant: Self.torchSize),
            torchButton.heightAnchor.constraint(equalToConstant: Self.torchSize),

            hintContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hintContainer.bottomAnchor.constraint(equalTo: shutterButton.topAnchor, constant: -20),
            hintContainer.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            hintContainer.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),

            hintLabel.topAnchor.constraint(equalTo: hintContainer.topAnchor, constant: 6),
            hintLabel.bottomAnchor.constraint(equalTo: hintContainer.bottomAnchor, constant: -6),
            hintLabel.leadingAnchor.constraint(equalTo: hintContainer.leadingAnchor, constant: 12),
            hintLabel.trailingAnchor.constraint(equalTo: hintContainer.trailingAnchor, constant: -12),
        ])
    }

    /// C5 content: `video.slash`, the message, and "Choose from library".
    private func setUpUnavailable() {
        let icon = UIImageView(image: UIImage(
            systemName: "video.slash",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 34, weight: .regular)
        ))
        icon.tintColor = UIColor.white.withAlphaComponent(0.8)
        icon.isAccessibilityElement = false

        let message = UILabel()
        message.text = "The camera isn't available right now."
        message.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: UIFont.systemFont(ofSize: 17, weight: .regular))
        message.adjustsFontForContentSizeCategory = true
        message.textColor = .white
        message.textAlignment = .center
        message.numberOfLines = 0

        var config = UIButton.Configuration.filled()
        var titleAttributes = AttributeContainer()
        titleAttributes.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: UIFont.systemFont(ofSize: 17, weight: .semibold))
        config.attributedTitle = AttributedString("Choose from library", attributes: titleAttributes)
        config.baseBackgroundColor = .white
        config.baseForegroundColor = Self.inkColor
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 24, bottom: 14, trailing: 24)
        let libraryButton = UIButton(configuration: config)
        libraryButton.addTarget(self, action: #selector(chooseLibrary), for: .touchUpInside)
        libraryButton.translatesAutoresizingMaskIntoConstraints = false

        unavailableStack.axis = .vertical
        unavailableStack.alignment = .center
        unavailableStack.spacing = 16
        unavailableStack.addArrangedSubview(icon)
        unavailableStack.addArrangedSubview(message)
        unavailableStack.addArrangedSubview(libraryButton)
        unavailableStack.isHidden = true
        unavailableStack.alpha = 0
        unavailableStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(unavailableStack)

        NSLayoutConstraint.activate([
            unavailableStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            unavailableStack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            unavailableStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            unavailableStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            libraryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
            libraryButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 240),
        ])
    }

    private static var deviceHasTorch: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)?.hasTorch ?? false
    }

    private func updateTorchAppearance() {
        let config = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        let name = isTorchOn ? "bolt.fill" : "bolt.slash.fill"
        let tint: UIColor = isTorchOn ? Self.inkColor : .white
        let image = UIImage(systemName: name, withConfiguration: config)?
            .withTintColor(tint, renderingMode: .alwaysOriginal)
        torchButton.setImage(image, for: .normal)
        torchButton.backgroundColor = isTorchOn
            ? UIColor.white.withAlphaComponent(0.9)
            : UIColor.black.withAlphaComponent(0.45)
        torchButton.accessibilityValue = isTorchOn ? "On" : "Off"
    }

    // MARK: - Actions

    @objc private func cancel() {
        onCancel?()
    }

    @objc private func chooseLibrary() {
        if let onChooseLibrary {
            onChooseLibrary()
        } else {
            onCancel?()
        }
    }

    /// M1: disc α .8, scale .92 (no scale under Reduce Motion).
    @objc private func shutterDown() {
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        UIView.animate(withDuration: 0.15, delay: 0, options: [.curveEaseOut, .beginFromCurrentState], animations: {
            self.shutterDisc.alpha = 0.8
            if !reduceMotion {
                self.shutterDisc.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
            }
        }, completion: nil)
    }

    @objc private func shutterReleased() {
        restoreShutter(discAlpha: 1)
    }

    private func restoreShutter(discAlpha: CGFloat) {
        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            usingSpringWithDamping: 1,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState],
            animations: {
                self.shutterDisc.alpha = discAlpha
                self.shutterDisc.transform = .identity
            },
            completion: nil
        )
    }

    @objc private func capture() {
        guard isConfigured else {
            restoreShutter(discAlpha: 1)
            return
        }
        shutterButton.isEnabled = false
        // Capturing: disc α .5 until the photo returns (05 §2.44).
        restoreShutter(discAlpha: 0.5)

        // Freeze the geometry for this capture while we are still on the main thread.
        pendingCrop = (guideRect(in: view.bounds), view.bounds.size)

        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    /// M2: one dip to 60 % black (60 ms in, 100 ms out), well under 3 flashes a second.
    private func blinkPreview() {
        blinkView.alpha = 0
        UIView.animateKeyframes(withDuration: 0.16, delay: 0, options: [], animations: {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.375) {
                self.blinkView.alpha = 0.6
            }
            UIView.addKeyframe(withRelativeStartTime: 0.375, relativeDuration: 0.625) {
                self.blinkView.alpha = 0
            }
        }, completion: nil)
    }

    private func photoReturned() {
        shutterButton.isEnabled = true
        restoreShutter(discAlpha: 1)
    }

    @objc private func toggleTorch() {
        guard Self.deviceHasTorch else { return }
        setTorch(on: !isTorchOn)
    }

    private func setTorch(on: Bool) {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            isTorchOn = on
            updateTorchAppearance()
        } catch {
            // The torch is a convenience; failing to set it must never break capture.
        }
    }
}

// MARK: - Photo delegate

extension ScanCameraViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        DispatchQueue.main.async { [weak self] in
            self?.blinkPreview()
            Haptics.shutter()
        }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let captured = UIImage(data: data) else {
            DispatchQueue.main.async { [weak self] in self?.photoReturned() }
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.photoReturned()

            // 1. Bake the EXIF orientation into the pixels so pixel coordinates match
            //    what the preview showed.
            let upright = captured.uprightedForCropping()

            guard let cgImage = upright.cgImage, let crop = self.pendingCrop else {
                self.setTorch(on: false)
                self.onCapture?(upright)
                return
            }
            self.pendingCrop = nil

            // 2. Crop with the exact geometry the guide box was drawn from.
            let rect = Self.imageCropRect(
                guideRect: crop.guide,
                layerSize: crop.layerSize,
                imagePixelSize: CGSize(width: cgImage.width, height: cgImage.height)
            )

            guard rect.width > 1, rect.height > 1, let cropped = cgImage.cropping(to: rect) else {
                self.setTorch(on: false)
                self.onCapture?(upright)
                return
            }

            self.setTorch(on: false)
            self.onCapture?(UIImage(cgImage: cropped, scale: 1, orientation: .up))
        }
    }
}

// MARK: - Orientation normalisation

extension UIImage {
    /// Redraws the image with its orientation applied, so `cgImage` pixel coordinates
    /// match `size`. A camera capture is a landscape buffer plus an orientation flag;
    /// cropping the raw buffer with rects derived from `size` silently swaps the axes.
    func uprightedForCropping() -> UIImage {
        guard imageOrientation != .up else { return self }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        let pixelSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: pixelSize, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: pixelSize))
        }
    }
}

// MARK: - Overlay

/// The guide box (05 §2.44): outside dimmed black α .35, a 2 pt white α .9
/// rounded rect (r 16, continuous) on the exact crop geometry.
private final class ScanGuideOverlayView: UIView {
    var guideRect: CGRect = .zero {
        didSet {
            guard guideRect != oldValue else { return }
            setNeedsDisplay()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), guideRect != .zero else { return }

        let box = UIBezierPath(roundedRect: guideRect, cornerRadius: 16)

        // Dim everything outside the guide box.
        ctx.setFillColor(UIColor.black.withAlphaComponent(0.35).cgColor)
        ctx.fill(rect)
        ctx.setBlendMode(.clear)
        ctx.addPath(box.cgPath)
        ctx.fillPath()
        ctx.setBlendMode(.normal)

        // The frame itself.
        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.9).cgColor)
        ctx.setLineWidth(2)
        ctx.addPath(box.cgPath)
        ctx.strokePath()
    }
}

// MARK: - Crop editor

/// Free-form crop, after the photo is taken: drag the corners or edges to fit
/// the item, drag inside to move the frame. Long, thin items (a pen, a knife,
/// a banknote) no longer have to be analysed with a square of background.
///
/// Works in fractions of the image (0...1), so the result doesn't depend on the
/// screen size, and always on the original photo, so a crop can be widened again.
struct CropEditorView: View {
    let image: UIImage
    /// The current crop, if the photo was cropped before.
    let initialCrop: CGRect?
    let onCancel: () -> Void
    /// nil means "no crop" (the whole photo).
    let onDone: (CGRect?) -> Void

    enum Handle: Equatable {
        case move, outside
        case top, bottom, left, right
        case topLeft, topRight, bottomLeft, bottomRight
    }

    private static let fullImage = CGRect(x: 0, y: 0, width: 1, height: 1)
    /// Smallest crop side, in points on screen.
    private static let minimumSide: CGFloat = 64
    /// How far from a corner or edge a touch still grabs it, in points.
    private static let grabDistance: CGFloat = 32

    @State private var crop: CGRect = CropEditorView.fullImage
    @State private var handle: Handle?
    @State private var dragStartCrop: CGRect?
    /// One haptic per drag when the frame reaches its minimum size (06 §3.2).
    @State private var didHitMinimum = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let imageRect = Self.fittedRect(
                    for: image.size,
                    in: CGRect(origin: .zero, size: geo.size).insetBy(dx: 24, dy: 24)
                )
                ZStack(alignment: .topLeading) {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: imageRect.width, height: imageRect.height)
                        .position(x: imageRect.midX, y: imageRect.midY)

                    CropOverlay(
                        cropRect: screenRect(for: crop, in: imageRect),
                        imageRect: imageRect,
                        showsGrid: handle != nil && handle != .outside
                    )
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(dragGesture(imageRect: imageRect))
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Crop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.wwBarText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone(Self.isFullImage(crop) ? nil : crop)
                    }
                    .buttonStyle(.wwBarTextProminent)
                    .fontWeight(.semibold)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    Text("Drag the corners to fit the item. Less background, better match.")
                        .wwFont(.subhead)
                        .foregroundStyle(Color.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Reset") {
                        // 06 M5: standard motion; instant under Reduce Motion.
                        withAnimation(reduceMotion ? nil : WW.Motion.animation(.standard, reduceMotion: false)) {
                            crop = Self.fullImage
                        }
                    }
                    .buttonStyle(.wwPressable)
                    .wwFont(.button)
                    .foregroundStyle(Color.white)
                    .frame(minHeight: WW.Size.minTarget)
                    .disabled(Self.isFullImage(crop))
                    .opacity(Self.isFullImage(crop) ? 0.4 : 1)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
        }
        .tint(.white)
        .preferredColorScheme(.dark)
        .onAppear {
            if let initialCrop { crop = initialCrop }
        }
    }

    // MARK: Gesture

    private func dragGesture(imageRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if handle == nil {
                    dragStartCrop = crop
                    handle = Self.grabbedHandle(at: value.startLocation, in: screenRect(for: crop, in: imageRect))
                }
                guard let handle, let start = dragStartCrop, imageRect.width > 0, imageRect.height > 0 else { return }
                let delta = CGSize(
                    width: value.translation.width / imageRect.width,
                    height: value.translation.height / imageRect.height
                )
                let minimum = CGSize(
                    width: min(1, Self.minimumSide / imageRect.width),
                    height: min(1, Self.minimumSide / imageRect.height)
                )
                let next = Self.adjusted(start, by: delta, handle: handle, minimumSize: minimum)
                if handle != .move, !didHitMinimum,
                   !Self.isAtMinimum(crop, minimumSize: minimum), Self.isAtMinimum(next, minimumSize: minimum) {
                    didHitMinimum = true
                    Haptics.impact(.rigid, intensity: 0.5)
                }
                crop = next
            }
            .onEnded { _ in
                handle = nil
                dragStartCrop = nil
                didHitMinimum = false
            }
    }

    // MARK: Geometry (pure)

    /// The image fitted (aspect fit) and centred in `bounds`.
    static func fittedRect(for size: CGSize, in bounds: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0, bounds.width > 0, bounds.height > 0 else { return bounds }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let width = size.width * scale
        let height = size.height * scale
        return CGRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height)
    }

    private func screenRect(for crop: CGRect, in imageRect: CGRect) -> CGRect {
        CGRect(
            x: imageRect.minX + crop.minX * imageRect.width,
            y: imageRect.minY + crop.minY * imageRect.height,
            width: crop.width * imageRect.width,
            height: crop.height * imageRect.height
        )
    }

    /// Which part of the crop frame a touch at `point` grabs. Corners win over
    /// edges, edges over moving.
    static func grabbedHandle(at point: CGPoint, in rect: CGRect) -> Handle {
        let reach = grabDistance
        let nearLeft = abs(point.x - rect.minX) < reach
        let nearRight = abs(point.x - rect.maxX) < reach
        let nearTop = abs(point.y - rect.minY) < reach
        let nearBottom = abs(point.y - rect.maxY) < reach
        let alongX = point.x > rect.minX - reach && point.x < rect.maxX + reach
        let alongY = point.y > rect.minY - reach && point.y < rect.maxY + reach

        if nearTop && nearLeft { return .topLeft }
        if nearTop && nearRight { return .topRight }
        if nearBottom && nearLeft { return .bottomLeft }
        if nearBottom && nearRight { return .bottomRight }
        if nearTop && alongX { return .top }
        if nearBottom && alongX { return .bottom }
        if nearLeft && alongY { return .left }
        if nearRight && alongY { return .right }
        if rect.contains(point) { return .move }
        return .outside
    }

    /// `start` moved or resized by `delta` (fractions of the image), kept inside
    /// the image and no smaller than `minimumSize`.
    static func adjusted(_ start: CGRect, by delta: CGSize, handle: Handle, minimumSize: CGSize) -> CGRect {
        switch handle {
        case .outside:
            return start
        case .move:
            let x = min(max(start.minX + delta.width, 0), 1 - start.width)
            let y = min(max(start.minY + delta.height, 0), 1 - start.height)
            return CGRect(x: x, y: y, width: start.width, height: start.height)
        default:
            break
        }

        var minX = start.minX, minY = start.minY, maxX = start.maxX, maxY = start.maxY
        if [.left, .topLeft, .bottomLeft].contains(handle) {
            minX = min(max(start.minX + delta.width, 0), maxX - minimumSize.width)
        }
        if [.right, .topRight, .bottomRight].contains(handle) {
            maxX = max(min(start.maxX + delta.width, 1), minX + minimumSize.width)
        }
        if [.top, .topLeft, .topRight].contains(handle) {
            minY = min(max(start.minY + delta.height, 0), maxY - minimumSize.height)
        }
        if [.bottom, .bottomLeft, .bottomRight].contains(handle) {
            maxY = max(min(start.maxY + delta.height, 1), minY + minimumSize.height)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// The frame is as small as it may get on either axis.
    static func isAtMinimum(_ rect: CGRect, minimumSize: CGSize) -> Bool {
        rect.width <= minimumSize.width + 0.0001 || rect.height <= minimumSize.height + 0.0001
    }

    static func isFullImage(_ rect: CGRect) -> Bool {
        rect.minX < 0.005 && rect.minY < 0.005 && rect.maxX > 0.995 && rect.maxY > 0.995
    }
}

/// Dimmed surroundings, a thin frame, thick corner marks, and a rule-of-thirds
/// grid while dragging.
private struct CropOverlay: View {
    let cropRect: CGRect
    let imageRect: CGRect
    let showsGrid: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                path.addRect(imageRect)
                path.addRect(cropRect)
            }
            .fill(Color.black.opacity(0.62), style: FillStyle(eoFill: true))

            if showsGrid {
                Path { path in
                    for i in 1...2 {
                        let x = cropRect.minX + cropRect.width * CGFloat(i) / 3
                        path.move(to: CGPoint(x: x, y: cropRect.minY))
                        path.addLine(to: CGPoint(x: x, y: cropRect.maxY))
                        let y = cropRect.minY + cropRect.height * CGFloat(i) / 3
                        path.move(to: CGPoint(x: cropRect.minX, y: y))
                        path.addLine(to: CGPoint(x: cropRect.maxX, y: y))
                    }
                }
                .stroke(Color.white.opacity(0.45), lineWidth: 0.5)
            }

            Path { path in
                path.addRect(cropRect)
            }
            .stroke(Color.white.opacity(0.9), lineWidth: 1)

            Path { path in
                let r = cropRect
                let arm = min(22, r.width / 2, r.height / 2)
                // top left
                path.move(to: CGPoint(x: r.minX, y: r.minY + arm))
                path.addLine(to: CGPoint(x: r.minX, y: r.minY))
                path.addLine(to: CGPoint(x: r.minX + arm, y: r.minY))
                // top right
                path.move(to: CGPoint(x: r.maxX - arm, y: r.minY))
                path.addLine(to: CGPoint(x: r.maxX, y: r.minY))
                path.addLine(to: CGPoint(x: r.maxX, y: r.minY + arm))
                // bottom right
                path.move(to: CGPoint(x: r.maxX, y: r.maxY - arm))
                path.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
                path.addLine(to: CGPoint(x: r.maxX - arm, y: r.maxY))
                // bottom left
                path.move(to: CGPoint(x: r.minX + arm, y: r.maxY))
                path.addLine(to: CGPoint(x: r.minX, y: r.maxY))
                path.addLine(to: CGPoint(x: r.minX, y: r.maxY - arm))
            }
            .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .square, lineJoin: .miter))
        }
        .allowsHitTesting(false)
    }
}
