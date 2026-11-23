import SwiftUI

/// Removes empty asset margins once so sizing reflects the visible brand artwork.
@MainActor
enum OperatorLogoArtwork {
    private static var lightCache: [String: UIImage] = [:]
    private static var darkCache: [String: UIImage] = [:]

    static func image(for code: String, colorScheme: ColorScheme = .light) -> UIImage? {
        if colorScheme == .dark {
            if let cached = darkCache[code] { return cached }
            guard let original = image(for: code) else { return nil }
            guard let dark = darkImage(original) else { return nil }
            darkCache[code] = dark
            return dark
        }
        if let cached = lightCache[code] { return cached }
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
        lightCache[code] = artwork
        return artwork
    }

    private static func darkImage(_ original: UIImage) -> UIImage? {
        guard let source = original.cgImage,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: source.width, height: source.height, bitsPerComponent: 8,
                  bytesPerRow: source.width * 4, space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        let byteCount = context.bytesPerRow * source.height
        let offsets = stride(from: 0, to: byteCount, by: 4)
        let hasTransparency = offsets.contains { pixels[$0 + 3] < 16 }
        let mattePixels = hasTransparency ? [] : Array(UnsafeBufferPointer(start: pixels, count: byteCount))

        for offset in offsets {
            let originalAlpha = Double(pixels[offset + 3]) / 255
            guard originalAlpha > 0 else { continue }
            var red = Double(pixels[offset]) / 255 / originalAlpha
            var green = Double(pixels[offset + 1]) / 255 / originalAlpha
            var blue = Double(pixels[offset + 2]) / 255 / originalAlpha
            var alpha = originalAlpha
            if !hasTransparency {
                let ink = SIMD3(1 - red, 1 - green, 1 - blue)
                let strength = max(ink.x, ink.y, ink.z)
                let whiteCutoff = 0.05
                guard strength > whiteCutoff else {
                    pixels.advanced(by: offset).update(repeating: 0, count: 4)
                    continue
                }

                // Compare a pale edge with nearby solid ink of the same hue to undo the white matte.
                let direction = ink / strength
                let reference = matteReference(pixels: mattePixels, at: offset, direction: direction,
                    strength: strength, width: source.width, height: source.height)
                alpha *= (strength - whiteCutoff) / (reference - whiteCutoff)
                let foreground = SIMD3<Double>(repeating: 1) - direction * reference
                red = foreground.x
                green = foreground.y
                blue = foreground.z
            }

            let chroma = max(red, green, blue) - min(red, green, blue)
            let minimumLuminance = 0.26 + 0.45 * max(0, 1 - chroma / 0.30)
            let linearRed = linearRGB(red)
            let linearGreen = linearRGB(green)
            let linearBlue = linearRGB(blue)
            let luminance = 0.2126 * linearRed + 0.7152 * linearGreen + 0.0722 * linearBlue

            // Brighten strong brand colours before lifting the remaining contrast towards white.
            let peak = max(linearRed, linearGreen, linearBlue)
            let colourWeight = min(1, max(0, (chroma - 0.12) / 0.24))
            let maximumGain = luminance > 0 && luminance < minimumLuminance
                ? min(minimumLuminance / luminance, 1 / peak)
                : 1
            let gain = 1 + (maximumGain - 1) * colourWeight
            let gainedLuminance = luminance * gain
            let lift = gainedLuminance < minimumLuminance
                ? (minimumLuminance - gainedLuminance) / (1 - gainedLuminance)
                : 0
            pixels[offset] = premultipliedSRGB(linearRed * gain, lift: lift, alpha: alpha)
            pixels[offset + 1] = premultipliedSRGB(linearGreen * gain, lift: lift, alpha: alpha)
            pixels[offset + 2] = premultipliedSRGB(linearBlue * gain, lift: lift, alpha: alpha)
            pixels[offset + 3] = UInt8((alpha * 255).rounded())
        }

        guard let image = context.makeImage() else { return nil }
        return UIImage(cgImage: image, scale: original.scale, orientation: original.imageOrientation)
    }

    private static func matteReference(pixels: [UInt8], at offset: Int, direction: SIMD3<Double>,
                                       strength: Double, width: Int, height: Int) -> Double {
        let pixel = offset / 4
        let x = pixel % width
        let y = pixel / width
        var strongestInk = max(0.40, strength)

        for row in max(0, y - 2)...min(height - 1, y + 2) {
            for column in max(0, x - 2)...min(width - 1, x + 2) {
                let candidate = (row * width + column) * 4
                let ink = SIMD3(255 - Double(pixels[candidate]), 255 - Double(pixels[candidate + 1]),
                                255 - Double(pixels[candidate + 2])) / 255
                let strength = max(ink.x, ink.y, ink.z)
                guard strength > strongestInk else { continue }
                let difference = ink / strength - direction
                guard max(abs(difference.x), abs(difference.y), abs(difference.z)) < 0.22 else { continue }
                strongestInk = max(strongestInk, strength)
            }
        }
        return strongestInk
    }

    private static func linearRGB(_ channel: Double) -> Double {
        if channel <= 0.04045 { return channel / 12.92 }
        return pow((channel + 0.055) / 1.055, 2.4)
    }

    private static func premultipliedSRGB(_ channel: Double, lift: Double, alpha: Double) -> UInt8 {
        let brightened = channel + (1 - channel) * lift
        let encoded = brightened <= 0.0031308 ? 12.92 * brightened : 1.055 * pow(brightened, 1 / 2.4) - 0.055
        return UInt8((min(1, max(0, encoded)) * alpha * 255).rounded())
    }
}

struct OperatorLogo: View {
    let name: String
    let code: String?
    var height: CGFloat = 32
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            let code = operatorCode
            let vectorName = "Operator\(code ?? "")Vector"
            if let vector = UIImage(named: vectorName) {
                // Draw the asset by name so SwiftUI uses the vector and its appearance variant.
                artwork(Image(vectorName), size: vector.size, fillHeight: code == "GR")
            } else if let code, let raster = OperatorLogoArtwork.image(for: code, colorScheme: colorScheme) {
                artwork(Image(uiImage: raster).interpolation(.high), size: raster.size, lightBackground: true)
            } else {
                Text(name)
            }
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    private func artwork(_ image: Image, size: CGSize, fillHeight: Bool = false, lightBackground: Bool = false) -> some View {
        let scale = height / 32
        let ratio = size.width / max(size.height, 1)
        let width = min(100, fillHeight ? 28 * ratio : max(48, (1800 * ratio).squareRoot())) * scale
        return image
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: width, height: min(28 * scale, width / ratio))
            .padding(2 * scale)
            .background(lightBackground && colorScheme == .light ? .white : .clear, in: RoundedRectangle(cornerRadius: 3))
            .frame(width: 104 * scale, height: height, alignment: .trailing)
            .accessibilityLabel(operatorCode == "LM" ? "London Northwestern Railway and West Midlands Railway" : name)
    }

    private var operatorCode: String? {
        let fallback = [
            "Great Northern": "GN",
            "Thameslink": "TL",
            "LNR & WMR": "LM",
            "West Midlands Trains": "LM",
            "WM Trains": "LM"
        ]
        return (code ?? fallback[name])?.uppercased()
    }

}
