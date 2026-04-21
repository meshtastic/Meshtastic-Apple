//
//  RouteDataPackageGenerator.swift
//  Meshtastic
//
//  Converts route CoT XML (b-m-r) into iTAK-importable KML data packages.
//  iTAK (like ATAK) ignores route CoT events from TCP streaming — routes
//  must be imported as KML files. This generator extracts waypoints from
//  the SDK-reconstructed route XML and packages them as a KML LineString
//  inside a MissionPackageManifest v2 zip saved to the app's Documents folder.
//

import Foundation
import OSLog

enum RouteDataPackageGenerator {

    struct RouteKmlResult {
        let kml: String
        let routeUid: String
        let routeName: String
    }

    // MARK: - KML Generation

    /// Extract waypoints from route CoT XML and generate a KML LineString.
    /// Returns nil if fewer than 2 waypoints are found.
    static func generateKml(routeXml: String) -> RouteKmlResult? {
        // Extract route UID from <event uid="...">
        guard let uidMatch = routeXml.range(of: #"<event\s[^>]*\buid="([^"]*)"#, options: .regularExpression),
              let uidCapture = routeXml[uidMatch].range(of: #"uid="([^"]*)"#, options: .regularExpression) else {
            return nil
        }
        let uidAttr = String(routeXml[uidCapture])
        let uid = String(uidAttr.dropFirst(5).dropLast(1)) // strip uid=" and trailing "

        // Extract route name from <contact callsign="...">
        let name: String
        if let csMatch = routeXml.range(of: #"<contact\s[^>]*\bcallsign="([^"]*)"#, options: .regularExpression),
           let csCapture = routeXml[csMatch].range(of: #"callsign="([^"]*)"#, options: .regularExpression) {
            let csAttr = String(routeXml[csCapture])
            name = String(csAttr.dropFirst(10).dropLast(1)) // strip callsign=" and trailing "
        } else {
            name = "Mesh Route"
        }

        // Extract waypoints from <link ... point="lat,lon,hae" .../> elements
        let linkPattern = #"<link\s[^>]*\bpoint="([^"]*)"[^>]*/>"#
        guard let linkRegex = try? NSRegularExpression(pattern: linkPattern, options: []) else {
            return nil
        }
        let nsRange = NSRange(routeXml.startIndex..., in: routeXml)
        let matches = linkRegex.matches(in: routeXml, range: nsRange)

        var kmlCoords: [String] = []
        for match in matches {
            guard match.numberOfRanges >= 2,
                  let pointRange = Range(match.range(at: 1), in: routeXml) else { continue }
            let point = String(routeXml[pointRange]) // "lat,lon,hae" or "lat,lon"
            let parts = point.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 2 else { continue }
            let lat = parts[0]
            let lon = parts[1]
            let hae = parts.count >= 3 ? parts[2] : "0"
            // KML coordinate order is lon,lat,hae (opposite of CoT's lat,lon,hae)
            kmlCoords.append("\(lon),\(lat),\(hae)")
        }

        guard kmlCoords.count >= 2 else { return nil }

        Logger.tak.info("Route KML: \(kmlCoords.count) waypoints, first=\(kmlCoords.first ?? "none")")

        let escapedName = escapeXml(name)
        let kml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <kml xmlns="http://www.opengis.net/kml/2.2">
          <Document>
            <name>\(escapedName)</name>
            <Placemark>
              <name>\(escapedName)</name>
              <Style>
                <LineStyle><color>ff0000ff</color><width>3</width></LineStyle>
              </Style>
              <LineString>
                <coordinates>
        \(kmlCoords.map { "          \($0)" }.joined(separator: "\n"))
                </coordinates>
              </LineString>
            </Placemark>
          </Document>
        </kml>
        """

        return RouteKmlResult(kml: kml, routeUid: uid, routeName: name)
    }

    // MARK: - Data Package Generation

    /// Generate a complete data package (zip) containing the route as KML.
    /// Returns (fileName, zipData) or nil if the route XML can't be parsed.
    static func generateDataPackage(routeXml: String) -> (fileName: String, zipData: Data)? {
        guard let result = generateKml(routeXml: routeXml) else { return nil }

        let kmlFileName = "\(result.routeUid).kml"
        let zipFileName = "\(result.routeUid).zip"

        let manifest = """
        <MissionPackageManifest version="2">
          <Configuration>
            <Parameter name="uid" value="Meshtastic Route.\(result.routeUid)"/>
            <Parameter name="name" value="\(escapeXml(result.routeName))"/>
            <Parameter name="onReceiveDelete" value="true"/>
          </Configuration>
          <Contents>
            <Content ignore="false" zipEntry="\(kmlFileName)"/>
          </Contents>
        </MissionPackageManifest>
        """

        // Create temp directory with KML + manifest, then zip via NSFileCoordinator
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("route_pkg_\(result.routeUid)")

        do {
            if fileManager.fileExists(atPath: tempDir.path) {
                try fileManager.removeItem(at: tempDir)
            }
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

            try result.kml.write(to: tempDir.appendingPathComponent(kmlFileName), atomically: true, encoding: .utf8)
            try manifest.write(to: tempDir.appendingPathComponent("manifest.xml"), atomically: true, encoding: .utf8)

            // Create zip using NSFileCoordinator (same pattern as TAKDataPackageGenerator)
            var zipData: Data?
            var coordinatorError: NSError?
            let coordinator = NSFileCoordinator()

            coordinator.coordinate(readingItemAt: tempDir, options: .forUploading, error: &coordinatorError) { zipURL in
                zipData = try? Data(contentsOf: zipURL)
            }

            try? fileManager.removeItem(at: tempDir)

            if let coordinatorError {
                Logger.tak.error("Route zip coordinator error: \(coordinatorError.localizedDescription)")
                return nil
            }
            guard let data = zipData else {
                Logger.tak.error("Route zip data was nil")
                return nil
            }

            return (zipFileName, data)
        } catch {
            Logger.tak.error("Route data package generation failed: \(error.localizedDescription)")
            try? fileManager.removeItem(at: tempDir)
            return nil
        }
    }

    // MARK: - Save to Documents

    /// Save a data package zip to Documents/TAK Routes/. Returns the file URL on success.
    static func saveToDocuments(fileName: String, zipData: Data) -> URL? {
        let fileManager = FileManager.default
        guard let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            Logger.tak.error("Could not get Documents directory")
            return nil
        }

        let routesDir = documentsDir.appendingPathComponent("TAK Routes")
        do {
            try fileManager.createDirectory(at: routesDir, withIntermediateDirectories: true)
            let fileURL = routesDir.appendingPathComponent(fileName)
            try zipData.write(to: fileURL)
            return fileURL
        } catch {
            Logger.tak.error("Failed to save route data package: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Helpers

    /// Extract route name from CoT XML for notification display.
    static func extractRouteName(routeXml: String) -> String? {
        guard let csMatch = routeXml.range(of: #"<contact\s[^>]*\bcallsign="([^"]*)"#, options: .regularExpression),
              let csCapture = routeXml[csMatch].range(of: #"callsign="([^"]*)"#, options: .regularExpression) else {
            return nil
        }
        let csAttr = String(routeXml[csCapture])
        return String(csAttr.dropFirst(10).dropLast(1))
    }

    private static func escapeXml(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
