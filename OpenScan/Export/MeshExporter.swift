import Foundation
import simd

enum MeshExportError: Error, LocalizedError {
    case emptyMesh

    var errorDescription: String? {
        switch self {
        case .emptyMesh: "Nothing to export."
        }
    }
}

/// Pure serializers for a scanned mesh. No ARKit dependency, so they run in unit tests and the simulator.
enum MeshExporter {

    // MARK: PLY (binary little-endian)

    static func ply(_ mesh: ScanMesh, classificationColors: Bool = true) throws -> Data {
        guard !mesh.isEmpty else { throw MeshExportError.emptyMesh }
        let m = mesh.merged()
        let faceCount = m.triangleCount
        let hasVertexColor = !m.vertexColors.isEmpty
        let faceColors = classificationColors && !hasVertexColor
        var header = """
        ply
        format binary_little_endian 1.0
        comment OpenScan
        element vertex \(m.positions.count)
        property float x
        property float y
        property float z
        property float nx
        property float ny
        property float nz

        """
        if hasVertexColor {
            header += "property uchar red\nproperty uchar green\nproperty uchar blue\n"
        }
        header += "element face \(faceCount)\nproperty list uchar uint vertex_indices\n"
        if faceColors {
            header += "property uchar red\nproperty uchar green\nproperty uchar blue\n"
        }
        header += "end_header\n"

        var data = Data(header.utf8)
        data.reserveCapacity(data.count + m.positions.count * 27 + faceCount * (13 + 3))

        for i in 0..<m.positions.count {
            let p = m.positions[i], n = m.normals[i]
            for f in [p.x, p.y, p.z, n.x, n.y, n.z] { append(&data, f.bitPattern.littleEndian) }
            if hasVertexColor { data.append(contentsOf: m.vertexColors[(i * 3)..<(i * 3 + 3)]) }
        }
        for t in 0..<faceCount {
            data.append(3)
            for k in 0..<3 { append(&data, m.indices[t * 3 + k].littleEndian) }
            if faceColors {
                let c = ClassificationPalette.rgb(for: t < m.faceClasses.count ? m.faceClasses[t] : 0)
                data.append(contentsOf: [c.0, c.1, c.2])
            }
        }
        return data
    }

    // MARK: OBJ

    static func obj(_ mesh: ScanMesh) throws -> Data {
        guard !mesh.isEmpty else { throw MeshExportError.emptyMesh }
        let m = mesh.merged()
        var out = "# OpenScan\n"
        out.reserveCapacity(m.positions.count * 48 + m.triangleCount * 24)
        let hasColor = !m.vertexColors.isEmpty
        for (i, p) in m.positions.enumerated() {
            if hasColor {
                // "v x y z r g b" (0-1) is read by MeshLab, Blender and CloudCompare.
                let r = Float(m.vertexColors[i * 3]) / 255
                let g = Float(m.vertexColors[i * 3 + 1]) / 255
                let b = Float(m.vertexColors[i * 3 + 2]) / 255
                out += "v \(p.x) \(p.y) \(p.z) \(r) \(g) \(b)\n"
            } else {
                out += "v \(p.x) \(p.y) \(p.z)\n"
            }
        }
        for n in m.normals { out += "vn \(n.x) \(n.y) \(n.z)\n" }
        for t in 0..<m.triangleCount {
            let a = m.indices[t * 3] + 1, b = m.indices[t * 3 + 1] + 1, c = m.indices[t * 3 + 2] + 1
            out += "f \(a)//\(a) \(b)//\(b) \(c)//\(c)\n"
        }
        return Data(out.utf8)
    }

    // MARK: USD / USDZ

    /// A USDA scene: one mesh, per-vertex normals, per-face classification colors, meters, Y-up (ARKit's frame).
    static func usda(_ mesh: ScanMesh) throws -> Data {
        guard !mesh.isEmpty else { throw MeshExportError.emptyMesh }
        let m = mesh.merged()
        func v3(_ v: SIMD3<Float>) -> String { "(\(v.x), \(v.y), \(v.z))" }
        let b = mesh.bounds!
        let perVertex = !m.vertexColors.isEmpty
        let colors: [String]
        if perVertex {
            colors = (0..<m.positions.count).map { i in
                "(\(Float(m.vertexColors[i * 3]) / 255), \(Float(m.vertexColors[i * 3 + 1]) / 255), "
                    + "\(Float(m.vertexColors[i * 3 + 2]) / 255))"
            }
        } else {
            colors = (0..<m.triangleCount).map { t in
                let c = ClassificationPalette.rgb(for: t < m.faceClasses.count ? m.faceClasses[t] : 0)
                return "(\(Float(c.0) / 255), \(Float(c.1) / 255), \(Float(c.2) / 255))"
            }
        }
        let colorInterpolation = perVertex ? "vertex" : "uniform"

        let out = """
        #usda 1.0
        (
            defaultPrim = "Scan"
            metersPerUnit = 1
            upAxis = "Y"
        )

        def Xform "Scan"
        {
            def Mesh "Mesh" (
                prepend apiSchemas = ["MaterialBindingAPI"]
            )
            {
                uniform bool doubleSided = true
                uniform token subdivisionScheme = "none"
                float3[] extent = [\(v3(b.min)), \(v3(b.max))]
                int[] faceVertexCounts = [\(Array(repeating: "3", count: m.triangleCount).joined(separator: ", "))]
                int[] faceVertexIndices = [\(m.indices.map(String.init).joined(separator: ", "))]
                point3f[] points = [\(m.positions.map(v3).joined(separator: ", "))]
                normal3f[] normals = [\(m.normals.map(v3).joined(separator: ", "))] (
                    interpolation = "vertex"
                )
                color3f[] primvars:displayColor = [\(colors.joined(separator: ", "))] (
                    interpolation = "\(colorInterpolation)"
                )
                rel material:binding = </Scan/Materials/Scan>
            }

            def Scope "Materials"
            {
                def Material "Scan"
                {
                    token outputs:surface.connect = </Scan/Materials/Scan/Surface.outputs:surface>

                    def Shader "Surface"
                    {
                        uniform token info:id = "UsdPreviewSurface"
                        color3f inputs:diffuseColor.connect = </Scan/Materials/Scan/Color.outputs:result>
                        float inputs:roughness = 0.9
                        token outputs:surface
                    }

                    def Shader "Color"
                    {
                        uniform token info:id = "UsdPrimvarReader_float3"
                        string inputs:varname = "displayColor"
                        float3 inputs:fallback = (0.7, 0.7, 0.7)
                        float3 outputs:result
                    }
                }
            }
        }

        """
        return Data(out.utf8)
    }

    static func usdz(_ mesh: ScanMesh, to url: URL) throws {
        let packaged = USDZPackager.package(fileName: "scan.usda", contents: try usda(mesh))
        try packaged.write(to: url, options: .atomic)
    }

    // MARK: Dispatch

    static func write(_ mesh: ScanMesh, format: ExportFormat, to url: URL) throws {
        switch format {
        case .ply: try ply(mesh).write(to: url, options: .atomic)
        case .obj: try obj(mesh).write(to: url, options: .atomic)
        case .usdz: try usdz(mesh, to: url)
        }
    }

    private static func append<T: FixedWidthInteger>(_ data: inout Data, _ value: T) {
        withUnsafeBytes(of: value) { data.append(contentsOf: $0) }
    }
}

/// Colors for ARMeshClassification raw values (none, wall, floor, ceiling, table, seat, window, door).
enum ClassificationPalette {
    static func rgb(for raw: UInt8) -> (UInt8, UInt8, UInt8) {
        switch raw {
        case 1: (200, 200, 205)   // wall
        case 2: (90, 170, 110)    // floor
        case 3: (235, 235, 240)   // ceiling
        case 4: (210, 150, 80)    // table
        case 5: (170, 100, 190)   // seat
        case 6: (90, 160, 230)    // window
        case 7: (200, 90, 80)     // door
        default: (150, 150, 155)  // none
        }
    }
}
