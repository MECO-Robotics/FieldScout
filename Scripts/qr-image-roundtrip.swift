import AppKit
import CoreImage
import Foundation
import Vision

guard let payload = ProcessInfo.processInfo.environment["QRSCOUT_CONTRACT_PAYLOAD"],
      let data = payload.data(using: .utf8),
      let filter = CIFilter(name: "CIQRCodeGenerator") else {
    fatalError("QRSCOUT_CONTRACT_PAYLOAD or QR generator is unavailable")
}

filter.setValue(data, forKey: "inputMessage")
filter.setValue("M", forKey: "inputCorrectionLevel")
guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
      let image = CIContext().createCGImage(output, from: output.extent) else {
    fatalError("Could not render QRScout payload")
}

let request = VNDetectBarcodesRequest()
request.symbologies = [.qr]
try VNImageRequestHandler(cgImage: image).perform([request])
let decoded = (request.results?.first as? VNBarcodeObservation)?.payloadStringValue
guard decoded == payload else {
    fatalError("Rendered QR code did not decode byte-for-byte")
}

print("QR image round-trip passed (\(payload.utf8.count) UTF-8 bytes).")
