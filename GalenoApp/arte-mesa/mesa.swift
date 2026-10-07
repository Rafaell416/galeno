import AppKit
import CoreImage

// La mesa del home a partir de la mesa que generó Rafa (vista por el lado corto): se endereza su tablero de madera y se
// recoloca en la perspectiva diagonal de la app (las mismas esquinas que `Mesa` en MesaScene.swift). El canto y las
// patas se pintan con la misma madera, oscurecida. Sale un PNG con transparencia a 3x del lienzo (704 × 352).
// uso: mesa entrada.jpg salida.png
let a = CommandLine.arguments
let k: CGFloat = 3, W: CGFloat = 704, H: CGFloat = 352
// Las esquinas del tablero en la app (puntos, origen arriba a la izquierda).
let backNear = CGPoint(x: 52, y: 228), backFar = CGPoint(x: 616, y: 146)
// Un paralelogramo: los dos extremos miden lo mismo y nada converge. El fondo (del borde de atrás al de delante) es
// el mismo vector en los dos extremos; se puede pasar otro para probar inclinaciones: mesa entrada salida dx dy
let depth = CGPoint(x: a.count > 4 ? Double(a[3])! : 70, y: a.count > 4 ? Double(a[4])! : 48)
let frontFar = CGPoint(x: backFar.x + depth.x, y: backFar.y + depth.y)
let frontNear = CGPoint(x: backNear.x + depth.x, y: backNear.y + depth.y)
let drop: CGFloat = 12, dropFar: CGFloat = 12
func px(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * k, y: (H - p.y) * k) }  // a píxeles, origen abajo (CoreImage/CG)
func down(_ p: CGPoint, _ d: CGFloat) -> CGPoint { CGPoint(x: p.x, y: p.y + d) }

let source = CIImage(contentsOf: URL(fileURLWithPath: a[1]))!
let sh = source.extent.height
func src(_ x: CGFloat, _ y: CGFloat) -> CIVector { CIVector(x: x, y: sh - y) }
// El tablero en la imagen de Rafa: lejos-izquierda, lejos-derecha, cerca-derecha, cerca-izquierda.
let flat = source.applyingFilter("CIPerspectiveCorrection", parameters: [
    "inputTopLeft": src(632, 537), "inputTopRight": src(938, 537),
    "inputBottomRight": src(1290, 1222), "inputBottomLeft": src(262, 1222),
])
// A grises, con las luces quemadas contenidas, sobre el tono del papel.
func toned(_ image: CIImage, gain: CGFloat) -> CIImage {
    image.applyingFilter("CIColorControls", parameters: ["inputSaturation": 0, "inputContrast": 0.92])
        .applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 243 / 255 * gain, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 238 / 255 * gain, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 226 / 255 * gain, w: 0),
        ])
}
func placed(_ image: CIImage, _ tl: CGPoint, _ tr: CGPoint, _ br: CGPoint, _ bl: CGPoint) -> CIImage {
    image.applyingFilter("CIPerspectiveTransform", parameters: [
        "inputTopLeft": CIVector(cgPoint: px(tl)), "inputTopRight": CIVector(cgPoint: px(tr)),
        "inputBottomRight": CIVector(cgPoint: px(br)), "inputBottomLeft": CIVector(cgPoint: px(bl)),
    ])
}
let top = placed(toned(flat, gain: 0.8), backFar, frontFar, frontNear, backNear)
// El canto: la misma madera, más oscura, estirada sobre el frente y el lado cercano.
let front = placed(toned(flat, gain: 0.36), frontFar, down(frontFar, dropFar), down(frontNear, drop), frontNear)
let side = placed(toned(flat, gain: 0.24), backNear, frontNear, down(frontNear, drop), down(backNear, drop))

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(W * k), height: Int(H * k), bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let ci = CIContext(options: [.workingColorSpace: space])
let canvas = CGRect(x: 0, y: 0, width: W * k, height: H * k)

func path(_ points: [CGPoint]) -> CGPath {
    let p = CGMutablePath(); p.addLines(between: points.map(px)); p.closeSubpath(); return p
}
// La sombra en el suelo: suave, bajo el tablero.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -36 * k), blur: 14 * k, color: CGColor(gray: 0, alpha: 0.34))
ctx.addPath(path([down(backNear, 4), down(backFar, 4), down(frontFar, 2), down(frontNear, 4)]))
ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fillPath()
ctx.restoreGState()
// (la figura que proyecta la sombra se borra: solo queda la sombra)
ctx.setBlendMode(.clear); ctx.addPath(path([down(backNear, 4), down(backFar, 4), down(frontFar, 2), down(frontNear, 4)])); ctx.fillPath()
ctx.setBlendMode(.normal)

// Las patas que se ven: madera oscura, con una arista más clara.
func leg(_ top: CGPoint, height: CGFloat, width: CGFloat) {
    let pts = [top, CGPoint(x: top.x + width, y: top.y - width * 0.2), CGPoint(x: top.x + width * 0.8, y: top.y + height - width * 0.2), CGPoint(x: top.x + width * 0.2, y: top.y + height)]
    ctx.addPath(path(pts)); ctx.setFillColor(CGColor(srgbRed: 0.13, green: 0.125, blue: 0.115, alpha: 1)); ctx.fillPath()
    ctx.move(to: px(pts[0])); ctx.addLine(to: px(pts[3]))
    ctx.setStrokeColor(CGColor(srgbRed: 0.42, green: 0.41, blue: 0.38, alpha: 1)); ctx.setLineWidth(1.2 * k); ctx.strokePath()
}
leg(CGPoint(x: backNear.x + 3, y: backNear.y + drop - 2), height: 50, width: 8)
leg(CGPoint(x: frontFar.x - 11, y: frontFar.y + dropFar - 2), height: 50, width: 8)
leg(CGPoint(x: frontNear.x + 4, y: frontNear.y + drop - 2), height: 50, width: 8)

for (image, quad) in [(side, [backNear, frontNear, down(frontNear, drop), down(backNear, drop)]),
                      (front, [frontNear, frontFar, down(frontFar, dropFar), down(frontNear, drop)]),
                      (top, [backNear, backFar, frontFar, frontNear])] {
    guard let cg = ci.createCGImage(image, from: canvas) else { continue }
    ctx.saveGState(); ctx.addPath(path(quad)); ctx.clip(); ctx.draw(cg, in: canvas); ctx.restoreGState()
}
// Las aristas del tablero: un filo claro delante y uno oscuro donde se junta con el canto.
ctx.setLineJoin(.round)
ctx.addPath(path([backNear, backFar, frontFar, frontNear])); ctx.setStrokeColor(CGColor(srgbRed: 0.16, green: 0.155, blue: 0.145, alpha: 1)); ctx.setLineWidth(1.0 * k); ctx.strokePath()
ctx.move(to: px(frontNear)); ctx.addLine(to: px(frontFar))
ctx.setStrokeColor(CGColor(srgbRed: 0.78, green: 0.76, blue: 0.71, alpha: 0.75)); ctx.setLineWidth(0.8 * k); ctx.strokePath()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[2]))
print("mesa", Int(W * k), Int(H * k))
