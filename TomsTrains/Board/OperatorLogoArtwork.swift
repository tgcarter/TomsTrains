import SwiftUI

/// Removes empty asset margins once so sizing reflects the visible brand artwork.
@MainActor
enum OperatorLogoArtwork {
    private static var cache: [String: UIImage] = [:]

    static func image(for code: String) -> UIImage? {
        if let cached = cache[code] { return cached }
        guard let original = UIImage(named: "Operator" + code),
              let source = original.cgImage else { return nil }
        let width = source.width
        let height = source.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let bounds: CGRect? = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return nil }
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            let bytes = buffer.bindMemory(to: UInt8.self)
            var left = width, top = height, right = -1, bottom = -1
            for y in 0..<height {
                for x in 0..<width {
                    let offset = (y * width + x) * 4
                    let alpha = Int(bytes[offset + 3])
                    // Ignore transparency and white backgrounds, including antialiased edges.
                    guard alpha > 24,
                          (0..<3).contains(where: { Int(bytes[offset + $0]) * 255 < 242 * alpha }) else { continue }
                    left = min(left, x); right = max(right, x)
                    top = min(top, y); bottom = max(bottom, y)
                }
            }
            guard right >= left, bottom >= top else { return nil }
            return CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
        }
        let artwork = bounds.flatMap { source.cropping(to: $0) }
            .map { UIImage(cgImage: $0, scale: original.scale, orientation: original.imageOrientation) } ?? original
        cache[code] = artwork
        return artwork
    }
}

struct OperatorLogo: View {
    let name: String
    let code: String?
    var height: CGFloat = 32
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 4) {
            if let image = operatorLogo {
                let ratio = image.size.width / max(image.size.height, 1)
                let scale = height / 32
                let width = min(100, max(48, (1800 * ratio).squareRoot())) * scale
                Group {
                    if colorScheme == .dark {
                        Color.white.mask {
                            Image(uiImage: image)
                                .resizable().scaledToFit()
                                .saturation(0).colorInvert().luminanceToAlpha()
                        }
                    } else {
                        Image(uiImage: image).resizable().scaledToFit()
                    }
                }
                    .frame(width: width, height: min(28 * scale, width / ratio))
                    .padding(2 * scale)
                    .background(colorScheme == .dark ? Color.clear : .white, in: RoundedRectangle(cornerRadius: 3))
                    .frame(width: 104 * scale, height: height, alignment: .trailing)
                    .accessibilityLabel(name)
            } else {
                Text(name)
            }
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    private var operatorLogo: UIImage? {
        let fallback = ["Great Northern": "GN", "Thameslink": "TL"]
        guard let code = code ?? fallback[name] else { return nil }
        return OperatorLogoArtwork.image(for: code.uppercased())
    }

}
