import AppKit
import CoreGraphics

// De un recorte con transparencia a una lámina para la mesa del home. Se recorta a un rectángulo (píxeles, origen
// arriba a la izquierda), se pasa a grises sobre el tono del papel y se iguala el tono (gamma y negros) con las
// demás. La figura se apoya en el tablero: en la franja de abajo la ropa se disuelve hacia la madera, pero lo claro
// y grande —manos, puños, papel— se queda entero, encima de la mesa. Los lados que la imagen cortaba en seco se
// difuminan. Sale a 720 px de alto.
// uso: lamina entrada.png salida.png x y ancho alto difIzq difDer franja gamma negros "x,y x,y …;x,y …"
// El último argumento son los contornos de lo que se queda encima de la mesa (manos, puños, papel), en píxeles de la
// lámina ya reducida (720 de alto), uno por polígono, separados por punto y coma.
let a = CommandLine.arguments
guard let source = NSImage(contentsOfFile: a[1])?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fatalError() }
let crop = CGRect(x: Double(a[3])!, y: Double(a[4])!, width: Double(a[5])!, height: Double(a[6])!)
let fadeL = Double(a[7])!, fadeR = Double(a[8])!, band = Double(a[9])!, gamma = Double(a[10])!, lift = Double(a[11])!
guard let cut = source.cropping(to: crop) else { fatalError("recorte fuera de la imagen") }
let h = 720, w = Int((crop.width / crop.height * 720).rounded())
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.interpolationQuality = .high
ctx.draw(cut, in: CGRect(x: 0, y: 0, width: w, height: h))
let p = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)

// La luminancia de cada píxel (sin premultiplicar) y su transparencia.
var gray = [Double](repeating: 0, count: w * h), alpha = [Double](repeating: 0, count: w * h)
for i in 0..<(w * h) {
    let al = Double(p[i * 4 + 3]) / 255
    alpha[i] = al
    if al > 0 { gray[i] = min(1, (0.299 * Double(p[i * 4]) + 0.587 * Double(p[i * 4 + 1]) + 0.114 * Double(p[i * 4 + 2])) / 255 / al) }
}
// Lo claro «y grande»: la luminancia muy desenfocada (dos pasadas de caja), para que el rayado del grabado en la ropa
// no cuente como claro y sí las manos, los puños y el papel.
func boxBlur(_ input: [Double], radius: Int) -> [Double] {
    var tmp = [Double](repeating: 0, count: w * h), out = [Double](repeating: 0, count: w * h)
    let n = Double(2 * radius + 1)
    for y in 0..<h {
        var sum = 0.0
        for x in -radius...radius { sum += input[y * w + min(max(x, 0), w - 1)] }
        for x in 0..<w {
            tmp[y * w + x] = sum / n
            sum += input[y * w + min(x + radius + 1, w - 1)] - input[y * w + max(x - radius, 0)]
        }
    }
    for x in 0..<w {
        var sum = 0.0
        for y in -radius...radius { sum += tmp[min(max(y, 0), h - 1) * w + x] }
        for y in 0..<h {
            out[y * w + x] = sum / n
            sum += tmp[min(y + radius + 1, h - 1) * w + x] - tmp[max(y - radius, 0) * w + x]
        }
    }
    return out
}
let weighted = zip(gray, alpha).map { $0 * $1 }
let soft = boxBlur(boxBlur(weighted, radius: 5), radius: 5)
// Los contornos de lo que se queda, pintados en una máscara y suavizados.
let maskCtx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
maskCtx.setFillColor(gray: 0, alpha: 1); maskCtx.fill(CGRect(x: 0, y: 0, width: w, height: h))
maskCtx.setFillColor(gray: 1, alpha: 1)
for polygon in (a.count > 12 ? a[12] : "").split(separator: ";") {
    let points = polygon.split(separator: " ").map { pair -> CGPoint in
        let xy = pair.split(separator: ","); return CGPoint(x: Double(xy[0])!, y: Double(h) - Double(xy[1])!)
    }
    guard points.count > 2 else { continue }
    maskCtx.addLines(between: points); maskCtx.closePath(); maskCtx.fillPath()
}
let m = maskCtx.data!.bindMemory(to: UInt8.self, capacity: w * h)
// La memoria de CoreGraphics va de arriba abajo, igual que `p`.
let region = boxBlur((0..<(w * h)).map { Double(m[$0]) / 255 }, radius: 4)
func smooth(_ x: Double, _ a: Double, _ b: Double) -> Double { let t = min(1, max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t) }

let paper = (243.0, 238.0, 226.0)
for y in 0..<h {
    for x in 0..<w {
        let i = y * w + x
        guard alpha[i] > 0 else { continue }
        var g = min(1, max(0, (gray[i] - 0.06) / 0.86))
        g = lift + (1 - lift) * pow(g, gamma)
        let fx = Double(x) / Double(w), fy = Double(y) / Double(h)
        var fade = 1.0
        if fadeL > 0 { fade *= min(1, fx / fadeL) }
        if fadeR > 0 { fade *= min(1, (1 - fx) / fadeR) }
        if band > 0, fy > 1 - band {
            // La ropa se disuelve hacia abajo; lo claro y grande se queda.
            let dissolve = smooth((1 - fy) / band, 0, 1)
            let keep = region[i] * smooth(soft[i], 0.26, 0.40)
            fade *= max(dissolve, keep)
            // Y se oscurece antes de irse: una tela clara a medio borrar sobre la madera parecería niebla.
            g *= max(keep, dissolve * dissolve)
        }
        fade *= min(1, (1 - fy) / 0.02)  // el último filo, siempre
        let out = alpha[i] * fade
        p[i * 4] = UInt8(g * paper.0 * out); p[i * 4 + 1] = UInt8(g * paper.1 * out); p[i * 4 + 2] = UInt8(g * paper.2 * out)
        p[i * 4 + 3] = UInt8(out * 255)
    }
}
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[2]))
print(w, h)
