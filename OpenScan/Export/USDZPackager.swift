import Foundation

/// Wraps a single USD(C) file into a .usdz archive.
///
/// ModelIO cannot write .usdz (`MDLAsset.canExportFileExtension("usdz")` is false), but it does write .usdc.
/// USDZ is an uncompressed ("stored") zip whose file data starts on a 64-byte boundary, so the package is
/// built directly here. Spec: https://openusd.org/release/spec_usdz.html
enum USDZPackager {
    static func package(fileName: String, contents: Data) -> Data {
        let name = Data(fileName.utf8)
        let crc = crc32(contents)
        let size = UInt32(contents.count)

        // Pad the local header's extra field so the file data lands on a 64-byte boundary.
        let base = 30 + name.count
        var extraLength = (64 - base % 64) % 64
        if extraLength > 0 && extraLength < 4 { extraLength += 64 }

        var out = Data()
        out.append(le32(0x04034b50)); out.append(le16(20)); out.append(le16(0)); out.append(le16(0))
        out.append(le16(0)); out.append(le16(0x21))              // DOS time 00:00, date 1980-01-01
        out.append(le32(crc)); out.append(le32(size)); out.append(le32(size))
        out.append(le16(UInt16(name.count))); out.append(le16(UInt16(extraLength)))
        out.append(name)
        if extraLength > 0 {
            out.append(le16(0x1986)); out.append(le16(UInt16(extraLength - 4)))
            out.append(Data(count: extraLength - 4))
        }
        precondition(out.count % 64 == 0, "USDZ file data must be 64-byte aligned")
        out.append(contents)

        let centralOffset = out.count
        var central = Data()
        central.append(le32(0x02014b50)); central.append(le16(20)); central.append(le16(20))
        central.append(le16(0)); central.append(le16(0)); central.append(le16(0)); central.append(le16(0x21))
        central.append(le32(crc)); central.append(le32(size)); central.append(le32(size))
        central.append(le16(UInt16(name.count))); central.append(le16(0)); central.append(le16(0))
        central.append(le16(0)); central.append(le16(0)); central.append(le32(0))
        central.append(le32(0))                                  // local header offset
        central.append(name)
        out.append(central)

        out.append(le32(0x06054b50)); out.append(le16(0)); out.append(le16(0))
        out.append(le16(1)); out.append(le16(1))
        out.append(le32(UInt32(central.count))); out.append(le32(UInt32(centralOffset))); out.append(le16(0))
        return out
    }

    private static func le16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    private static func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }

    private static let table: [UInt32] = (0..<256).map { n in
        (0..<8).reduce(UInt32(n)) { c, _ in c & 1 == 1 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
    }

    static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for byte in data { c = table[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }
}
