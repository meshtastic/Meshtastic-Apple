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
		guard let uid = attributeValue(in: routeXml, on: "event", named: "uid") else {
			return nil
		}

		let name = attributeValue(in: routeXml, on: "contact", named: "callsign") ?? "Mesh Route"

		// Extract waypoints from <link ... point="lat,lon,hae" .../> elements.
		// Match either single or double-quoted point attributes — the upstream
		// SDK builder happens to emit doubles, but CoTMessage.toXML() and any
		// third-party route generator could emit singles, and silently failing
		// on those would drop a valid route.
		let linkPattern = #"<link\b[^>]*\bpoint\s*=\s*(['"])([^'"]*)\1[^>]*/?>"#
		guard let linkRegex = try? NSRegularExpression(pattern: linkPattern, options: []) else {
			return nil
		}
		let nsRange = NSRange(routeXml.startIndex..., in: routeXml)
		let matches = linkRegex.matches(in: routeXml, range: nsRange)

		// Each `point` attribute comes from remote CoT XML and is otherwise
		// concatenated straight into the KML <coordinates> body, so anything
		// non-numeric — e.g. `1.0,2.0,3.0"></coordinates><...>injected</...><x x="`
		// — would either break KML parsing or inject markup into the data
		// package. Parse each component as `Double` and range-check it
		// against the geodetic bounds before re-emitting; HAE outside
		// roughly Earth-surface bounds is dropped to 0 since a bogus
		// altitude is much less harmful than a bogus lat/lon.
		var kmlCoords: [String] = []
		for match in matches {
			guard match.numberOfRanges >= 3,
				  let pointRange = Range(match.range(at: 2), in: routeXml) else { continue }
			let point = String(routeXml[pointRange]) // "lat,lon,hae" or "lat,lon"
			let parts = point.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
			guard parts.count >= 2,
				  let lat = Double(parts[0]), lat.isFinite, (-90.0...90.0).contains(lat),
				  let lon = Double(parts[1]), lon.isFinite, (-180.0...180.0).contains(lon)
			else { continue }
			let hae: Double
			if parts.count >= 3, let parsedHae = Double(parts[2]), parsedHae.isFinite,
			   (-12_000.0...100_000.0).contains(parsedHae) {
				hae = parsedHae
			} else {
				hae = 0
			}
			// KML coordinate order is lon,lat,hae (opposite of CoT's lat,lon,hae).
			// Format with `%g` to keep things compact and avoid locale-specific
			// commas which would corrupt the comma-delimited triplet.
			kmlCoords.append(String(format: "%g,%g,%g", locale: Locale(identifier: "en_US_POSIX"), lon, lat, hae))
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

		// routeUid comes from remote CoT XML so it must be treated as
		// untrusted input. Use two separate sanitizations:
		//   * `safeUid`        — strict alphanumeric/`-_.` form, used in
		//                        file names and the temp directory path so
		//                        a malicious UID can't escape to ../../ or
		//                        include filesystem-illegal characters.
		//   * `escapedManifestUid` — XML-escaped form for embedding inside
		//                        the manifest's attribute value, so `&`,
		//                        `<`, `>`, `"`, `'` don't break the XML.
		let safeUid = sanitizeForFilename(result.routeUid)
		let escapedManifestUid = escapeXml(result.routeUid)

		let kmlFileName = "\(safeUid).kml"
		let zipFileName = "\(safeUid).zip"

		let manifest = """
		<MissionPackageManifest version="2">
		  <Configuration>
		    <Parameter name="uid" value="Meshtastic Route.\(escapedManifestUid)"/>
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
		let tempDir = fileManager.temporaryDirectory.appendingPathComponent("route_pkg_\(safeUid)")

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
		attributeValue(in: routeXml, on: "contact", named: "callsign")
	}

	/// Pull `<element ... name="value">` or `<element ... name='value'>` from
	/// the first element matching `element`. Supports either quote style and
	/// arbitrary attribute order. Returns nil when the element / attribute
	/// is missing.
	static func attributeValue(in xml: String, on element: String, named attribute: String) -> String? {
		// Find the opening tag for the element.
		let openTagPattern = #"<"# + element + #"\b[^>]*>"#
		guard let tagRange = xml.range(of: openTagPattern, options: .regularExpression) else {
			return nil
		}
		let tag = String(xml[tagRange])

		// Match `name="value"` or `name='value'` inside that tag only.
		let attrPattern = #"\b"# + attribute + #"\s*=\s*(['"])([^'"]*)\1"#
		guard let attrRegex = try? NSRegularExpression(pattern: attrPattern, options: []) else {
			return nil
		}
		let nsRange = NSRange(tag.startIndex..., in: tag)
		guard let attrMatch = attrRegex.firstMatch(in: tag, range: nsRange),
			  attrMatch.numberOfRanges >= 3,
			  let valueRange = Range(attrMatch.range(at: 2), in: tag) else {
			return nil
		}
		return String(tag[valueRange])
	}

	/// Reduce a string to characters safe for use as a file name on
	/// case-preserving filesystems and APFS. Path separators (`/`, `\`),
	/// directory traversal sequences, NUL bytes, and other shell-sensitive
	/// characters are collapsed to `_`. A `route` placeholder is returned
	/// if the sanitized result is empty.
	static func sanitizeForFilename(_ input: String) -> String {
		let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
		var out = String(input.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
		// Collapse runs of `.` so we never create `..` or `...` directory
		// traversal segments, and trim leading dots so the result isn't a
		// hidden file or anchored to a different directory.
		while out.contains("..") {
			out = out.replacingOccurrences(of: "..", with: "_")
		}
		out = out.trimmingCharacters(in: CharacterSet(charactersIn: "."))
		return out.isEmpty ? "route" : out
	}

	private static func escapeXml(_ string: String) -> String {
		string
			.replacingOccurrences(of: "&", with: "&amp;")
			.replacingOccurrences(of: "<", with: "&lt;")
			.replacingOccurrences(of: ">", with: "&gt;")
			.replacingOccurrences(of: "\"", with: "&quot;")
			.replacingOccurrences(of: "'", with: "&apos;")
	}
}
