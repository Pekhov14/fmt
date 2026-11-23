import AppKit
import CoreGraphics
import Foundation

// Делает из квадратного исходника шаблонную иконку для MenuBarExtra.
// Кружок становится сплошной маской, светлые детали исходника — вырезанными.
// Система сама красит такую иконку в нужный цвет (тёмная тема и т.д.).

let args = CommandLine.arguments
guard args.count >= 3 else {
    fatalError("Использование: render-menubar-icon <source.png> <output.imageset>")
}

let sourceURL = URL(fileURLWithPath: args[1])
let outputURL = URL(fileURLWithPath: args[2])

guard let sourceData = try? Data(contentsOf: sourceURL),
      let source = CGImageSourceCreateWithData(sourceData as CFData, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fatalError("Не удалось прочитать \(sourceURL.path)")
}

let colorSpace = CGColorSpaceCreateDeviceRGB()
let width = image.width
let height = image.height
let bytesPerRow = width * 4

guard let context = CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: bytesPerRow,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
), let buffer = context.data else {
    fatalError("Не удалось создать контекст")
}

context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
let pixels = buffer.assumingMemoryBound(to: UInt8.self)
var sourceAlpha = [UInt8](repeating: 0, count: width * height)

for y in 0..<height {
    for x in 0..<width {
        let offset = y * bytesPerRow + x * 4
        let red = Double(pixels[offset]) / 255
        let green = Double(pixels[offset + 1]) / 255
        let blue = Double(pixels[offset + 2]) / 255
        let alpha = Double(pixels[offset + 3]) / 255
        sourceAlpha[y * width + x] = pixels[offset + 3]

        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let saturation = maximum == 0 ? 0 : (maximum - minimum) / maximum

        // Светлые детали (буква и декор) станут вырезанными в залитом кружке.
        let lightness = min(max((0.40 - saturation) / 0.35, 0), 1)
        let brightness = min(max(luminance / 0.75, 0), 1)
        let outAlpha = UInt8(min(255, (alpha * lightness * brightness * 255 * 1.25).rounded()))

        // Предумноженная белая: RGB==A, после снятия предумножения даёт белый.
        pixels[offset] = outAlpha
        pixels[offset + 1] = outAlpha
        pixels[offset + 2] = outAlpha
        pixels[offset + 3] = outAlpha
    }
}

guard let glyph = context.makeImage() else {
    fatalError("Не удалось получить шаблонное изображение")
}

/// Заливаем исходный кружок и вырезаем из него светлые детали: сплошной
/// силуэт заметнее в менюбаре, чем отдельные тонкие штрихи.
func filledPlate(glyph: CGImage, sourceAlpha: [UInt8], width: Int, height: Int) -> CGImage {
    let bytesPerRow = width * 4
    guard let glyphContext = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ), let outputContext = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ), let glyphBuffer = glyphContext.data, let outputBuffer = outputContext.data else {
        return glyph
    }

    glyphContext.draw(glyph, in: CGRect(x: 0, y: 0, width: width, height: height))
    let glyphPixels = glyphBuffer.assumingMemoryBound(to: UInt8.self)
    let output = outputBuffer.assumingMemoryBound(to: UInt8.self)

    for index in 0..<(width * height) {
        let offset = index * 4
        let cutout = Int(glyphPixels[offset + 3])
        let value = UInt8(Int(sourceAlpha[index]) * (255 - cutout) / 255)
        output[offset] = value
        output[offset + 1] = value
        output[offset + 2] = value
        output[offset + 3] = value
    }
    return outputContext.makeImage() ?? glyph
}

let template = filledPlate(glyph: glyph, sourceAlpha: sourceAlpha, width: width, height: height)

/// Обрезаем пустые поля, чтобы значок занимал всю иконку и был заметнее.
func croppedToContent(_ image: CGImage) -> CGImage {
    let width = image.width
    let height = image.height
    let bytesPerRow = width * 4
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ), let buffer = context.data else { return image }

    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    let pixels = buffer.assumingMemoryBound(to: UInt8.self)

    var minX = width, minY = height, maxX = -1, maxY = -1
    for y in 0..<height {
        for x in 0..<width {
            let offset = y * bytesPerRow + x * 4
            if pixels[offset + 3] > 51 {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
    }
    guard maxX >= minX else { return image }

    let centerX = (minX + maxX) / 2
    let centerY = (minY + maxY) / 2
    let side = min(
        max(width, height),
        Int(Double(max(maxX - minX + 1, maxY - minY + 1)) * 1.12)
    )
    let x = max(0, min(width - side, centerX - side / 2))
    let y = max(0, min(height - side, centerY - side / 2))
    return image.cropping(to: CGRect(x: x, y: y, width: side, height: side)) ?? image
}

func pngData(_ image: CGImage, size: Int) -> Data {
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("Не удалось создать контекст для \(size)px")
    }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    guard let resized = context.makeImage() else {
        fatalError("Не удалось изменить размер до \(size)px")
    }

    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        data, "public.png" as CFString, 1, nil
    ) else {
        fatalError("Не удалось создать PNG")
    }
    CGImageDestinationAddImage(destination, resized, nil)
    guard CGImageDestinationFinalize(destination) else {
        fatalError("Не удалось записать PNG")
    }
    return data as Data
}

let finalImage = croppedToContent(template)

try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
try pngData(finalImage, size: 22).write(to: outputURL.appendingPathComponent("menubar.png"))
try pngData(finalImage, size: 44).write(to: outputURL.appendingPathComponent("menubar@2x.png"))

let contents = """
{
  "images" : [
    { "filename" : "menubar.png", "idiom" : "mac", "scale" : "1x", "size" : "22x22" },
    { "filename" : "menubar@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "22x22" }
  ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "template-rendering-intent" : "template" }
}
"""
try contents.write(
    to: outputURL.appendingPathComponent("Contents.json"),
    atomically: true,
    encoding: .utf8
)

print("Иконка для менюбара: \(outputURL.path)")
