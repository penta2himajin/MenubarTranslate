import Foundation
import zlib

enum HTTPPayload {
    static func hexPrefix(_ data: Data, count: Int = 16) -> String {
        data.prefix(count).map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    static func unwrap(_ data: Data) -> Data {
        if isGzip(data), let out = gunzip(data) { return out }
        if isZlib(data), let out = inflateZlib(data) { return out }
        return data
    }

    static func isGzip(_ data: Data) -> Bool {
        data.count >= 2 && data[0] == 0x1f && data[1] == 0x8b
    }

    static func isZlib(_ data: Data) -> Bool {
        data.count >= 2 && data[0] == 0x78 && (data[1] == 0x01 || data[1] == 0x9c || data[1] == 0xda)
    }

    static func gunzip(_ data: Data) -> Data? {
        inflateWindow(data, windowBits: 16 + MAX_WBITS)
    }

    static func inflateZlib(_ data: Data) -> Data? {
        inflateWindow(data, windowBits: MAX_WBITS)
    }

    private static func inflateWindow(_ data: Data, windowBits: Int32) -> Data? {
        guard !data.isEmpty else { return nil }
        var stream = z_stream()
        var packed = [UInt8](data)
        let initStatus = inflateInit2_(&stream, windowBits, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initStatus == Z_OK else { return nil }
        defer { inflateEnd(&stream) }

        var output = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        var offset = 0
        while offset < packed.count {
            let remaining = packed.count - offset
            let status: Int32 = packed.withUnsafeMutableBufferPointer { src in
                buffer.withUnsafeMutableBufferPointer { dst in
                    stream.next_in = src.baseAddress?.advanced(by: offset)
                    stream.avail_in = uInt(remaining)
                    stream.next_out = dst.baseAddress
                    stream.avail_out = uInt(dst.count)
                    return zlib.inflate(&stream, Z_NO_FLUSH)
                }
            }
            let consumed = remaining - Int(stream.avail_in)
            offset += consumed
            let produced = buffer.count - Int(stream.avail_out)
            if produced > 0 { output.append(contentsOf: buffer.prefix(produced)) }
            if status == Z_STREAM_END { return output }
            if status != Z_OK, status != Z_BUF_ERROR { return nil }
            if consumed == 0, produced == 0 { return nil }
        }
        return output.isEmpty ? nil : output
    }
}
