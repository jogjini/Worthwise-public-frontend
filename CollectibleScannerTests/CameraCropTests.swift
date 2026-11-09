import XCTest
@testable import CollectibleScanner

/// The guide box the user frames and the crop applied to the capture come from the
/// same geometry. These tests pin that relationship down: the crop must be centred
/// where the guide box was, stay inside the image, and never depend on device size.
final class CameraCropTests: XCTestCase {

    private func guideRect(layer: CGSize, controlsHeight: CGFloat = 148, ratio: CGFloat = 0.84) -> CGRect {
        let available = max(0, layer.height - controlsHeight)
        let side = min(layer.width * ratio, available * 0.9)
        return CGRect(x: (layer.width - side) / 2, y: (available - side) / 2, width: side, height: side)
    }

    func testCropIsHorizontallyCentredOnTheSensor() {
        let layer = CGSize(width: 393, height: 852)      // iPhone 15
        let pixels = CGSize(width: 3024, height: 4032)   // 4:3 portrait capture
        let rect = ScanCameraViewController.imageCropRect(
            guideRect: guideRect(layer: layer),
            layerSize: layer,
            imagePixelSize: pixels
        )
        XCTAssertEqual(rect.midX, pixels.width / 2, accuracy: 2,
                       "a horizontally centred guide box must map to a horizontally centred crop")
    }

    func testCropStaysInsideTheImage() {
        let pixels = CGSize(width: 3024, height: 4032)
        // Every plausible device size, including small phones and iPad-ish aspects.
        for layer in [CGSize(width: 320, height: 568),
                      CGSize(width: 375, height: 667),
                      CGSize(width: 393, height: 852),
                      CGSize(width: 430, height: 932),
                      CGSize(width: 744, height: 1133)] {
            let rect = ScanCameraViewController.imageCropRect(
                guideRect: guideRect(layer: layer),
                layerSize: layer,
                imagePixelSize: pixels
            )
            XCTAssertGreaterThanOrEqual(rect.minX, 0, "\(layer)")
            XCTAssertGreaterThanOrEqual(rect.minY, 0, "\(layer)")
            XCTAssertLessThanOrEqual(rect.maxX, pixels.width, "\(layer)")
            XCTAssertLessThanOrEqual(rect.maxY, pixels.height, "\(layer)")
            XCTAssertGreaterThan(rect.width, 100, "crop should be a usable size at \(layer)")
        }
    }

    func testGuideBoxAboveCentreMapsAboveCentre() {
        // The guide box sits above the controls strip, so its centre is above the
        // layer's centre — the crop must be shifted the same way, not the opposite.
        let layer = CGSize(width: 393, height: 852)
        let pixels = CGSize(width: 3024, height: 4032)
        let guide = guideRect(layer: layer)
        XCTAssertLessThan(guide.midY, layer.height / 2, "precondition: guide sits high")

        let rect = ScanCameraViewController.imageCropRect(
            guideRect: guide, layerSize: layer, imagePixelSize: pixels
        )
        XCTAssertLessThan(rect.midY, pixels.height / 2,
                          "crop drifted the wrong way — this is the original shift bug")
    }

    func testSquareGuideStaysSquare() {
        let rect = ScanCameraViewController.imageCropRect(
            guideRect: CGRect(x: 30, y: 100, width: 300, height: 300),
            layerSize: CGSize(width: 393, height: 852),
            imagePixelSize: CGSize(width: 3024, height: 4032)
        )
        XCTAssertEqual(rect.width, rect.height, accuracy: 2)
    }

    func testDegenerateInputsReturnZeroInsteadOfCrashing() {
        XCTAssertEqual(
            ScanCameraViewController.imageCropRect(
                guideRect: CGRect(x: 0, y: 0, width: 100, height: 100),
                layerSize: .zero,
                imagePixelSize: CGSize(width: 100, height: 100)
            ),
            .zero
        )
    }
}
