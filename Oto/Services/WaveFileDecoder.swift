import Foundation

enum WaveFileDecoderError: LocalizedError {
    case invalidPCMFormat

    var errorDescription: String? {
        switch self {
        case .invalidPCMFormat:
            return "Audio must be a 16-bit mono 16 kHz WAV file."
        }
    }
}

enum WaveFileDecoder {
    static func decodePCM16Mono(url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        guard data.count >= 44 else {
            throw WaveFileDecoderError.invalidPCMFormat
        }

        let riff = String(data: data[0..<4], encoding: .ascii)
        let wave = String(data: data[8..<12], encoding: .ascii)
        guard riff == "RIFF", wave == "WAVE" else {
            throw WaveFileDecoderError.invalidPCMFormat
        }

        return stride(from: 44, to: data.count, by: 2).map { offset in
            data[offset..<min(offset + 2, data.count)].withUnsafeBytes { buffer in
                let sample = Int16(littleEndian: buffer.load(as: Int16.self))
                return max(-1.0, min(Float(sample) / 32_767.0, 1.0))
            }
        }
    }
}
