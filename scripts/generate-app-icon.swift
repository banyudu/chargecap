import AppKit

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high

NSColor.clear.setFill()
NSRect(origin: .zero, size: size).fill()

let body = NSBezierPath(
    roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896),
    xRadius: 210,
    yRadius: 210
)
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
shadow.shadowBlurRadius = 42
shadow.shadowOffset = NSSize(width: 0, height: -18)
shadow.set()

NSGradient(colors: [
    NSColor(calibratedRed: 0.08, green: 0.25, blue: 0.18, alpha: 1),
    NSColor(calibratedRed: 0.025, green: 0.09, blue: 0.065, alpha: 1),
])!.draw(in: body, angle: -90)
NSGraphicsContext.current?.cgContext.setShadow(offset: .zero, blur: 0, color: nil)

NSColor.white.withAlphaComponent(0.10).setStroke()
body.lineWidth = 6
body.stroke()

let battery = NSBezierPath(
    roundedRect: NSRect(x: 190, y: 410, width: 590, height: 250),
    xRadius: 72,
    yRadius: 72
)
NSColor.white.setStroke()
battery.lineWidth = 34
battery.stroke()

let fill = NSBezierPath(
    roundedRect: NSRect(x: 220, y: 440, width: 530 * 0.80, height: 190),
    xRadius: 48,
    yRadius: 48
)
NSGradient(colors: [
    NSColor(calibratedRed: 0.38, green: 0.94, blue: 0.58, alpha: 1),
    NSColor(calibratedRed: 0.13, green: 0.72, blue: 0.38, alpha: 1),
])!.draw(in: fill, angle: 0)

let terminal = NSBezierPath(
    roundedRect: NSRect(x: 786, y: 485, width: 54, height: 100),
    xRadius: 24,
    yRadius: 24
)
NSColor.white.setFill()
terminal.fill()

let text = "80" as NSString
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 118, weight: .bold),
    .foregroundColor: NSColor(calibratedWhite: 0.035, alpha: 0.90),
    .paragraphStyle: paragraph,
]
text.draw(
    in: NSRect(x: 220, y: 476, width: 454, height: 140),
    withAttributes: attributes
)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let representation = NSBitmapImageRep(data: tiff),
      let png = representation.representation(using: .png, properties: [:]) else {
    fatalError("Could not render icon")
}

try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
