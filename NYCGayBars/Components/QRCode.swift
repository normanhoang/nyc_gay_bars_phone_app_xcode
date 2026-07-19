import SwiftUI
import CoreImage.CIFilterBuiltins

/// Crisp QR image for a string using the built-in CoreImage generator.
/// Render with `.interpolation(.none)` so upscaling stays sharp.
func qrCodeImage(for string: String) -> UIImage? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(string.utf8)
    filter.correctionLevel = "M"
    guard let output = filter.outputImage else { return nil }
    // Scale up in CoreImage so the CGImage itself is high-res.
    let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
    guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
    return UIImage(cgImage: cg)
}
