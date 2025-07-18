import Foundation
import Compression

extension Data {
    /// Decompresses raw deflate data
    func zlibDecompressed() throws -> Data {
        guard self.count > 0 else { return Data() }

        // Try Foundation's zlib first
        do {
            let decompressedData = try (self as NSData).decompressed(using: .zlib) as Data
            print("Data+Zlib: Successfully decompressed with Foundation \(count) bytes to \(decompressedData.count) bytes")
            return decompressedData
        } catch {
            print("Data+Zlib: Foundation decompression failed: \(error), trying raw deflate...")
        }

        // Fallback to Compression framework with raw deflate
        let bufferSize = count * 10
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { destination.deallocate() }

        return try self.withUnsafeBytes { bytes in
            let source = bytes.bindMemory(to: UInt8.self)

            let result = compression_decode_buffer(
                destination, bufferSize,
                source.baseAddress!, count,
                nil, COMPRESSION_ZLIB
            )

            guard result > 0 else {
                print("Data+Zlib: Raw deflate decompression also failed, result size: \(result)")
                throw ZlibError.decompression
            }

            print("Data+Zlib: Successfully decompressed with raw deflate \(count) bytes to \(result) bytes")
            return Data(bytes: destination, count: result)
        }
    }
}

enum ZlibError: Error {
    case decompression

    var localizedDescription: String {
        switch self {
        case .decompression:
            return "Failed to decompress data"
        }
    }
}

enum GzipError: Error {
    case decompression

    var localizedDescription: String {
        switch self {
        case .decompression:
            return "Failed to decompress gzip data"
        }
    }
}