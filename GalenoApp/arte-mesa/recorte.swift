import AppKit
import CoreImage
import Vision

// Recorta el sujeto de una imagen con Vision (en este Mac, sin subir nada) y lo guarda como PNG con transparencia.
let args = CommandLine.arguments
let input = URL(fileURLWithPath: args[1]), output = URL(fileURLWithPath: args[2])
guard let source = CIImage(contentsOf: input) else { fatalError("no se pudo leer") }
let request = VNGenerateForegroundInstanceMaskRequest()
let handler = VNImageRequestHandler(ciImage: source)
try handler.perform([request])
guard let result = request.results?.first else { print("sin sujeto"); exit(1) }
print("instancias:", result.allInstances.count)
let buffer = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: false)
let image = CIImage(cvPixelBuffer: buffer)
let context = CIContext()
try context.writePNGRepresentation(of: image, to: output, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
