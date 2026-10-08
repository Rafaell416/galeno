import AVFoundation
import AppKit

// args: input output cropX cropY cropW cropH outW bitrate
let a = CommandLine.arguments
let input = URL(fileURLWithPath: a[1]), output = URL(fileURLWithPath: a[2])
let cx = Double(a[3])!, cy = Double(a[4])!, cw = Double(a[5])!, ch = Double(a[6])!
let outW = Int(a[7])!, bitrate = Int(a[8])!
let outH = Int((Double(outW) * ch / cw / 2).rounded()) * 2
let asset = AVURLAsset(url: input)
let duration = try await asset.load(.duration)
let track = try await asset.loadTracks(withMediaType: .video)[0]

let comp = AVMutableVideoComposition()
comp.renderSize = CGSize(width: outW, height: outH)
comp.frameDuration = CMTime(value: 1, timescale: 30)
let instr = AVMutableVideoCompositionInstruction()
instr.timeRange = CMTimeRange(start: .zero, duration: duration)
let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
let s = Double(outW) / cw
layer.setTransform(CGAffineTransform(translationX: -cx, y: -cy).concatenating(CGAffineTransform(scaleX: s, y: s)), at: .zero)
instr.layerInstructions = [layer]
comp.instructions = [instr]

let reader = try AVAssetReader(asset: asset)
let rout = AVAssetReaderVideoCompositionOutput(videoTracks: [track], videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
rout.videoComposition = comp
reader.add(rout)
try? FileManager.default.removeItem(at: output)
let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
let win = AVAssetWriterInput(mediaType: .video, outputSettings: [
  AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: outW, AVVideoHeightKey: outH,
  AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel, AVVideoMaxKeyFrameIntervalKey: 60],
])
win.expectsMediaDataInRealTime = false
writer.add(win)
writer.shouldOptimizeForNetworkUse = true
reader.startReading(); writer.startWriting(); writer.startSession(atSourceTime: .zero)
await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
  win.requestMediaDataWhenReady(on: DispatchQueue(label: "enc")) {
    while win.isReadyForMoreMediaData {
      if let buf = rout.copyNextSampleBuffer() { win.append(buf) } else { win.markAsFinished(); c.resume(); break }
    }
  }
}
await writer.finishWriting()
print("encoded \(outW)x\(outH):", writer.status.rawValue, writer.error?.localizedDescription ?? "ok")
