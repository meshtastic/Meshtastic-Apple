import Foundation
import zlib

struct NativeSitePlannerPageRef: Equatable, Sendable {
	var minNorth: Int
	var minWest: Int
}

struct NativeSitePlannerTerrainProvider: Sendable {
	var loadPage: @Sendable (NativeSitePlannerPageRef, Int) async throws -> [Int16]?

	static let live = NativeSitePlannerTerrainProvider { page, ippd in
		try await NativeSitePlannerTerrainService.shared.page(for: page, ippd: ippd)
	}

	static let seaLevel = NativeSitePlannerTerrainProvider { _, _ in
		nil
	}
}

struct NativeSitePlannerCoverageClient: Sendable {
	var terrainProvider: NativeSitePlannerTerrainProvider = .live
	var contourMaxDimension = 180
	var runChunkSize = 256

	func generateContours(request payload: SitePlannerCoverageRequest) async throws -> Data {
		try await NativeSitePlannerCoverageRunner.shared.generateContours(
			request: payload,
			terrainProvider: terrainProvider,
			contourMaxDimension: contourMaxDimension,
			runChunkSize: runChunkSize
		)
	}
}

enum NativeSitePlannerCoverageError: Error, LocalizedError {
	case engineFailed(String, Int32)
	case invalidRaster
	case invalidTerrain(String)
	case terrainUnavailable(String)
	case missingCoverage
	case unsupportedParameter(String)

	var errorDescription: String? {
		switch self {
		case .engineFailed(let operation, let code):
			return "Native Site Planner engine failed during \(operation) with code \(code)."
		case .invalidRaster:
			return "Native Site Planner engine returned an invalid coverage raster."
		case .invalidTerrain(let message):
			return "Terrain data could not be prepared: \(message)"
		case .terrainUnavailable(let tile):
			return "Terrain tile \(tile) could not be loaded. Check your connection and try again."
		case .missingCoverage:
			return "Native Site Planner did not produce any coverage bands for this node."
		case .unsupportedParameter(let message):
			return "Coverage settings are not supported: \(message)"
		}
	}
}

private actor NativeSitePlannerCoverageRunner {
	static let shared = NativeSitePlannerCoverageRunner()

	private let metersPerFoot = 0.3048
	private let maxRadiusMeters = 150_000.0
	private let maxRadiusMetersHD = 70_000.0

	func generateContours(
		request payload: SitePlannerCoverageRequest,
		terrainProvider: NativeSitePlannerTerrainProvider,
		contourMaxDimension: Int,
		runChunkSize: Int
	) async throws -> Data {
		let params = try engineParameters(for: payload)
		let handle = splat_create(
			payload.lat,
			payload.lon,
			params.txAltFeet,
			params.rxAltFeet,
			payload.frequencyMHz,
			params.erpWatts,
			payload.groundDielectric,
			payload.groundConductivity,
			payload.atmosphereBending,
			params.radioClimate,
			params.polarization,
			params.confidence,
			params.reliability,
			payload.clutterHeight,
			params.radiusKilometers,
			Int32(params.resolutionIppd)
		)
		try Self.check(handle, "splat_create")
		defer { splat_destroy(handle) }

		let pageCount = try Self.checkedCount(splat_page_count(handle), "splat_page_count")
		for pageIndex in 0..<pageCount {
			var pageInfo = [Int32](repeating: 0, count: 2)
			let infoResult = splat_page_info(handle, Int32(pageIndex), &pageInfo)
			try Self.check(infoResult, "splat_page_info")
			let pageRef = NativeSitePlannerPageRef(minNorth: Int(pageInfo[0]), minWest: Int(pageInfo[1]))
			if let page = try await terrainProvider.loadPage(pageRef, params.resolutionIppd) {
				let expectedCells = params.resolutionIppd * params.resolutionIppd
				guard page.count == expectedCells else {
					throw NativeSitePlannerCoverageError.invalidTerrain(
						"page \(pageRef.minNorth),\(pageRef.minWest) has \(page.count) cells; expected \(expectedCells)."
					)
				}
				let loadResult = page.withUnsafeBufferPointer { buffer in
					splat_load_page(handle, Int32(pageIndex), buffer.baseAddress)
				}
				try Self.check(loadResult, "splat_load_page")
			}
		}

		let radialCount = try Self.checkedCount(splat_radial_count(handle), "splat_radial_count")
		let chunk = max(1, runChunkSize)
		for start in stride(from: 0, to: radialCount, by: chunk) {
			try Task.checkCancellation()
			let count = min(chunk, radialCount - start)
			let runResult = splat_run_radials(handle, Int32(start), Int32(count))
			try Self.check(runResult, "splat_run_radials")
		}

		try Self.check(splat_rasterize(handle), "splat_rasterize")

		var regionValues = [Double](repeating: 0, count: 8)
		try Self.check(splat_region_info(handle, &regionValues), "splat_region_info")
		let width = Int(regionValues[0])
		let height = Int(regionValues[1])
		guard width > 0, height > 0 else {
			throw NativeSitePlannerCoverageError.invalidRaster
		}
		guard let signalPointer = splat_signal_ptr(handle),
			  let maskPointer = splat_mask_ptr(handle) else {
			throw NativeSitePlannerCoverageError.invalidRaster
		}

		let cellCount = width * height
		let signal = UnsafeBufferPointer(start: signalPointer, count: cellCount)
		let mask = UnsafeBufferPointer(start: maskPointer, count: cellCount)
		let bounds = CoverageBounds(
			north: regionValues[2],
			south: regionValues[3],
			east: regionValues[4],
			west: regionValues[5]
		)
		let result = CoverageRaster(width: width, height: height, signal: signal, mask: mask, bounds: bounds)
		return try Self.featureCollectionData(
			from: result,
			request: payload,
			maxDimension: contourMaxDimension
		)
	}

	private func engineParameters(for payload: SitePlannerCoverageRequest) throws -> EngineParameters {
		guard let radioClimate = Self.climateCodes[payload.radioClimate] else {
			throw NativeSitePlannerCoverageError.unsupportedParameter("unknown radio climate '\(payload.radioClimate)'.")
		}
		guard let polarization = Self.polarizationCodes[payload.polarization] else {
			throw NativeSitePlannerCoverageError.unsupportedParameter("unknown polarization '\(payload.polarization)'.")
		}

		let highResolution = payload.highResolution
		let radiusMeters = min(payload.radius, highResolution ? maxRadiusMetersHD : maxRadiusMeters)
		let erpWatts = Self.round2(pow(10.0, (payload.txPower + payload.txGain - payload.systemLoss - 30.0) / 10.0))
		return EngineParameters(
			txAltFeet: payload.txHeight / metersPerFoot,
			rxAltFeet: payload.rxHeight / metersPerFoot,
			erpWatts: erpWatts,
			radioClimate: radioClimate,
			polarization: polarization,
			confidence: Self.round2(payload.situationFraction / 100.0),
			reliability: Self.round2(payload.timeFraction / 100.0),
			radiusKilometers: radiusMeters / 1_000.0,
			resolutionIppd: highResolution ? 3_600 : 1_200
		)
	}

	private static func featureCollectionData(
		from raster: CoverageRaster,
		request: SitePlannerCoverageRequest,
		maxDimension: Int
	) throws -> Data {
		let floorDbm = max(request.minDbm, request.signalThreshold)
		let maxDbm = request.maxDbm
		let span = max(maxDbm - floorDbm, 1.0)
		let bandCount = 12
		let levels = (0..<bandCount).map { floorDbm + (span * Double($0)) / Double(bandCount) }
		let grid = Self.preparedGrid(from: raster, maxDimension: max(20, maxDimension), sentinel: floorDbm - max(6.0, span / Double(bandCount)))

		let features: [[String: Any]] = levels.compactMap { level in
			let polygons = Self.rowRunPolygons(for: grid, threshold: level)
			guard !polygons.isEmpty else { return nil }
			let color = Self.color(for: level, minDbm: request.minDbm, maxDbm: maxDbm, scale: request.colormap)
			return [
				"type": "Feature",
				"properties": [
					"dbm": Int(level.rounded()),
					"color": color,
					"fill": color,
					"fill-opacity": 0.45,
					"stroke": color,
					"stroke-width": 0.5,
					"stroke-opacity": 0.65,
					"label": ">= \(Int(level.rounded())) dBm",
					"source": "native-site-planner"
				],
				"geometry": [
					"type": "MultiPolygon",
					"coordinates": polygons
				]
			]
		}

		guard !features.isEmpty else {
			throw NativeSitePlannerCoverageError.missingCoverage
		}

		let collection: [String: Any] = [
			"type": "FeatureCollection",
			"features": features
		]
		let data = try JSONSerialization.data(withJSONObject: collection, options: [])
		_ = try JSONDecoder().decode(GeoJSONFeatureCollection.self, from: data)
		return data
	}

	private static func preparedGrid(from raster: CoverageRaster, maxDimension: Int, sentinel: Double) -> PreparedCoverageGrid {
		let stride = max(1, Int(ceil(Double(max(raster.width, raster.height)) / Double(maxDimension))))
		let width = Int(ceil(Double(raster.width) / Double(stride)))
		let height = Int(ceil(Double(raster.height) / Double(stride)))
		var values = [Double](repeating: sentinel, count: width * height)

		for outputY in 0..<height {
			for outputX in 0..<width {
				var sum = 0.0
				var count = 0
				let startY = outputY * stride
				let startX = outputX * stride
				let endY = min(startY + stride, raster.height)
				let endX = min(startX + stride, raster.width)
				for y in startY..<endY {
					for x in startX..<endX {
						let index = y * raster.width + x
						if raster.hasCoverage(at: index) {
							sum += Double(raster.signal[index]) - 200.0
							count += 1
						}
					}
				}
				if count > 0 {
					values[outputY * width + outputX] = sum / Double(count)
				}
			}
		}

		return PreparedCoverageGrid(
			width: width,
			height: height,
			values: values,
			bounds: raster.bounds
		)
	}

	private static func rowRunPolygons(for grid: PreparedCoverageGrid, threshold: Double) -> [[[[Double]]]] {
		let lonPerColumn = (grid.bounds.east - grid.bounds.west) / Double(grid.width)
		let latPerRow = (grid.bounds.north - grid.bounds.south) / Double(grid.height)
		var polygons: [[[[Double]]]] = []

		for y in 0..<grid.height {
			var x = 0
			while x < grid.width {
				while x < grid.width && grid.values[y * grid.width + x] < threshold {
					x += 1
				}
				guard x < grid.width else { break }
				let startX = x
				while x < grid.width && grid.values[y * grid.width + x] >= threshold {
					x += 1
				}
				let endX = x
				let west = grid.bounds.west + Double(startX) * lonPerColumn
				let east = grid.bounds.west + Double(endX) * lonPerColumn
				let north = grid.bounds.north - Double(y) * latPerRow
				let south = grid.bounds.north - Double(y + 1) * latPerRow
				let ring = [
					[west, south],
					[west, north],
					[east, north],
					[east, south],
					[west, south]
				]
				polygons.append([ring])
			}
		}

		return polygons
	}

	private static func color(for dbm: Double, minDbm: Double, maxDbm: Double, scale: String) -> String {
		let denominator = max(maxDbm - minDbm, 1.0)
		let t = min(1.0, max(0.0, (dbm - minDbm) / denominator))
		let ramp = scale.lowercased() == "viridis" ? viridisRamp : plasmaRamp
		let scaled = t * Double(ramp.count - 1)
		let lower = max(0, min(ramp.count - 1, Int(floor(scaled))))
		let upper = max(0, min(ramp.count - 1, lower + 1))
		let amount = scaled - Double(lower)
		let rgb = zip(ramp[lower], ramp[upper]).map { colorPair in
			Int((Double(colorPair.0) + (Double(colorPair.1) - Double(colorPair.0)) * amount).rounded())
		}
		return "rgb(\(rgb[0]), \(rgb[1]), \(rgb[2]))"
	}

	private static func check(_ result: Int32, _ operation: String) throws {
		if result < 0 {
			throw NativeSitePlannerCoverageError.engineFailed(operation, result)
		}
	}

	private static func checkedCount(_ result: Int32, _ operation: String) throws -> Int {
		try check(result, operation)
		return Int(result)
	}

	private static func round2(_ value: Double) -> Double {
		(value * 100.0).rounded() / 100.0
	}

	private static let climateCodes = [
		"equatorial": Int32(1),
		"continental_subtropical": Int32(2),
		"maritime_subtropical": Int32(3),
		"desert": Int32(4),
		"continental_temperate": Int32(5),
		"maritime_temperate_land": Int32(6),
		"maritime_temperate_sea": Int32(7)
	]

	private static let polarizationCodes = [
		"horizontal": Int32(0),
		"vertical": Int32(1)
	]

	private static let plasmaRamp = [
		[13, 8, 135],
		[75, 3, 161],
		[125, 3, 168],
		[168, 34, 150],
		[203, 70, 121],
		[229, 107, 93],
		[248, 148, 65],
		[253, 195, 40],
		[240, 249, 33]
	]

	private static let viridisRamp = [
		[68, 1, 84],
		[70, 50, 126],
		[54, 92, 141],
		[39, 127, 142],
		[31, 161, 136],
		[74, 193, 109],
		[159, 218, 58],
		[253, 231, 37]
	]
}

actor NativeSitePlannerTerrainService {
	static let shared = NativeSitePlannerTerrainService()

	private let fileManager: FileManager
	private let session: URLSession
	private let cacheDirectory: URL

	init(session: URLSession = .shared) {
		let fileManager = FileManager.default
		self.fileManager = fileManager
		self.session = session
		let baseDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
		self.cacheDirectory = baseDirectory
			.appendingPathComponent("SitePlannerTerrain", isDirectory: true)
			.appendingPathComponent("v1", isDirectory: true)
	}

	func page(for page: NativeSitePlannerPageRef, ippd: Int) async throws -> [Int16]? {
		guard ippd == 1_200 || ippd == 3_600 else {
			throw NativeSitePlannerCoverageError.invalidTerrain("unsupported resolution \(ippd).")
		}

		try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
		let tileName = Self.tileName(for: page)
		let pageURL = cacheDirectory.appendingPathComponent("page_\(ippd)_\(tileName).s16")
		let missingURL = cacheDirectory.appendingPathComponent("page_\(ippd)_\(tileName).missing")
		if fileManager.fileExists(atPath: missingURL.path) {
			return nil
		}
		if fileManager.fileExists(atPath: pageURL.path) {
			let data = try Data(contentsOf: pageURL)
			return try Self.decodePageData(data, expectedCells: ippd * ippd)
		}

		guard let hgt = try await downloadTile(named: tileName) else {
			fileManager.createFile(atPath: missingURL.path, contents: Data())
			return nil
		}

		let pageData = try Self.pageData(fromHGT: hgt, ippd: ippd)
		let encodedPage = Self.encodePageData(pageData)
		try encodedPage.write(to: pageURL, options: .atomic)
		return pageData
	}

	private func downloadTile(named tileName: String) async throws -> Data? {
		var lastError: Error?
		for url in Self.tileURLs(for: tileName) {
			do {
				let (data, response) = try await session.data(from: url)
				guard let httpResponse = response as? HTTPURLResponse else {
					throw NativeSitePlannerCoverageError.invalidTerrain("invalid terrain response.")
				}
				if httpResponse.statusCode == 404 || httpResponse.statusCode == 403 {
					continue
				}
				guard (200...299).contains(httpResponse.statusCode) else {
					throw NativeSitePlannerCoverageError.terrainUnavailable(tileName)
				}
				return try Self.gunzip(data)
			} catch {
				lastError = error
			}
		}
		if let lastError {
			throw lastError
		}
		return nil
	}

	static func tileName(for page: NativeSitePlannerPageRef) -> String {
		let lat = page.minNorth
		let lon = signedFloorLongitude(forMinWest: page.minWest)
		let ns = lat >= 0 ? "N" : "S"
		let ew = lon >= 0 ? "E" : "W"
		return String(format: "%@%02d%@%03d", ns, abs(lat), ew, abs(lon))
	}

	static func signedFloorLongitude(forMinWest minWest: Int) -> Int {
		minWest < 180 ? -(minWest + 1) : 359 - minWest
	}

	static func tileURLs(for tileName: String) -> [URL] {
		let directory = String(tileName.prefix(3))
		return [
			URL(string: "https://elevation-tiles-prod.s3.amazonaws.com/v2/skadi/\(directory)/\(tileName).hgt.gz")!,
			URL(string: "https://elevation-tiles-prod.s3.amazonaws.com/skadi/\(directory)/\(tileName).hgt.gz")!
		]
	}

	static func pageData(fromHGT hgt: Data, ippd: Int) throws -> [Int16] {
		let full = try parseHGT(hgt)
		if ippd == 3_600 {
			return try srtm2sdfTransform(full, pageSize: 3_600)
		}
		return try srtm2sdfTransform(downsampleAverage(full), pageSize: 1_200)
	}

	private static func parseHGT(_ data: Data) throws -> [Int16] {
		let cellCount = hgtSize * hgtSize
		guard data.count >= cellCount * 2 else {
			throw NativeSitePlannerCoverageError.invalidTerrain("HGT tile too small: \(data.count) bytes.")
		}
		var output = [Int16](repeating: 0, count: cellCount)
		data.withUnsafeBytes { rawBuffer in
			let bytes = rawBuffer.bindMemory(to: UInt8.self)
			for index in 0..<cellCount {
				let byteOffset = index * 2
				let value = UInt16(bytes[byteOffset]) << 8 | UInt16(bytes[byteOffset + 1])
				output[index] = Int16(bitPattern: value)
			}
		}
		return output
	}

	private static func downsampleAverage(_ source: [Int16]) -> [Int16] {
		let ratio = Double(hgtSize) / Double(downsampledSize)
		var output = [Int16](repeating: 0, count: downsampledSize * downsampledSize)
		var low = [Int](repeating: 0, count: downsampledSize)
		var high = [Int](repeating: 0, count: downsampledSize)
		var lowWeight = [Double](repeating: 0, count: downsampledSize)
		var highWeight = [Double](repeating: 0, count: downsampledSize)

		for destination in 0..<downsampledSize {
			let start = Double(destination) * ratio
			let end = Double(destination + 1) * ratio
			let lowIndex = Int(floor(start))
			let highIndex = min(Int(ceil(end)), hgtSize)
			low[destination] = lowIndex
			high[destination] = highIndex
			lowWeight[destination] = min(Double(lowIndex + 1), end) - start
			highWeight[destination] = end - max(Double(highIndex - 1), start)
		}

		for y in 0..<downsampledSize {
			for x in 0..<downsampledSize {
				var total = 0.0
				var weight = 0.0
				for sourceY in low[y]..<high[y] {
					let yWeight = sourceY == low[y] ? lowWeight[y] : (sourceY == high[y] - 1 ? highWeight[y] : 1.0)
					let row = sourceY * hgtSize
					for sourceX in low[x]..<high[x] {
						let value = source[row + sourceX]
						guard value != srtmNoData else { continue }
						let xWeight = sourceX == low[x] ? lowWeight[x] : (sourceX == high[x] - 1 ? highWeight[x] : 1.0)
						let pixelWeight = xWeight * yWeight
						total += Double(value) * pixelWeight
						weight += pixelWeight
					}
				}
				if weight == 0 {
					output[y * downsampledSize + x] = srtmNoData
				} else {
					let value = total / weight
					output[y * downsampledSize + x] = Int16(value >= 0 ? floor(value + 0.5) : ceil(value - 0.5))
				}
			}
		}
		return output
	}

	private static func srtm2sdfTransform(_ grid: [Int16], pageSize: Int) throws -> [Int16] {
		let side = pageSize + 1
		guard grid.count == side * side else {
			throw NativeSitePlannerCoverageError.invalidTerrain("expected \(side * side) terrain cells, got \(grid.count).")
		}

		let maxPageIndex = pageSize - 1
		let minimumElevation = Int32(0)
		var srtm = grid.map { Int32($0) }
		for index in srtm.indices {
			srtm[index] = min(Int32(Int16.max), max(Int32(Int16.min), srtm[index]))
		}

		func index(_ y: Int, _ x: Int) -> Int {
			y * side + x
		}

		func value(_ y: Int, _ x: Int) -> Int32 {
			srtm[index(y, x)]
		}

		func averageTerrain(y: Int, x: Int) {
			let badValue = value(y, x)
			var accumulator = Int32(0)
			var count = Int32(0)
			var temp = Int32(0)

			func consider(_ yy: Int, _ xx: Int) {
				temp = value(yy, xx)
				if temp > badValue {
					accumulator += temp
					count += 1
				}
			}

			if y >= 2 { consider(y - 1, x) }
			if y <= maxPageIndex { consider(y + 1, x) }
			if y >= 2 && x <= maxPageIndex - 1 { consider(y - 1, x + 1) }
			if x <= maxPageIndex - 1 { consider(y, x + 1) }
			if x <= maxPageIndex - 1 && y <= maxPageIndex { consider(y + 1, x + 1) }
			if x >= 1 && y >= 2 { consider(y - 1, x - 1) }
			if x >= 1 { consider(y, x - 1) }
			if y <= maxPageIndex && x >= 1 { consider(y + 1, x - 1) }
			if count != 0 {
				temp = Int32((Double(accumulator) / Double(count) + 0.5).rounded(.towardZero))
			}
			srtm[index(y, x)] = temp > minimumElevation ? temp : minimumElevation
		}

		var output = [Int16](repeating: 0, count: pageSize * pageSize)
		var outputIndex = 0
		for y in stride(from: pageSize, through: 1, by: -1) {
			for x in stride(from: maxPageIndex, through: 0, by: -1) {
				let terrainValue = value(y, x)
				if terrainValue < minimumElevation {
					averageTerrain(y: y, x: x)
					output[outputIndex] = Int16(clamping: value(y, x))
				} else {
					output[outputIndex] = Int16(clamping: terrainValue)
				}
				outputIndex += 1
			}
		}
		return output
	}

	private static func gunzip(_ data: Data) throws -> Data {
		var input = [UInt8](data)
		let inputCount = input.count
		var output = [UInt8](repeating: 0, count: max(data.count * 4, 64 * 1_024))
		var stream = z_stream()
		let initResult = inflateInit2_(&stream, MAX_WBITS + 16, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
		guard initResult == Z_OK else {
			throw NativeSitePlannerCoverageError.invalidTerrain("gzip inflate init failed with \(initResult).")
		}
		defer { inflateEnd(&stream) }

		let inflateResult = input.withUnsafeMutableBytes { inputBuffer -> Int32 in
			stream.next_in = inputBuffer.bindMemory(to: Bytef.self).baseAddress
			stream.avail_in = uInt(inputCount)
			while true {
				if Int(stream.total_out) == output.count {
					output.append(contentsOf: repeatElement(0, count: output.count))
				}
				let outputOffset = Int(stream.total_out)
				let outputAvailable = output.count - outputOffset
				let status = output.withUnsafeMutableBytes { outputBuffer -> Int32 in
					stream.next_out = outputBuffer.bindMemory(to: Bytef.self).baseAddress?.advanced(by: outputOffset)
					stream.avail_out = uInt(outputAvailable)
					return inflate(&stream, Z_NO_FLUSH)
				}
				if status == Z_STREAM_END || status != Z_OK {
					return status
				}
			}
		}
		guard inflateResult == Z_STREAM_END else {
			throw NativeSitePlannerCoverageError.invalidTerrain("gzip inflate failed with \(inflateResult).")
		}
		return Data(output.prefix(Int(stream.total_out)))
	}

	private static func decodePageData(_ data: Data, expectedCells: Int) throws -> [Int16] {
		guard data.count == expectedCells * 2 else {
			throw NativeSitePlannerCoverageError.invalidTerrain("cached terrain page has \(data.count) bytes; expected \(expectedCells * 2).")
		}
		var output = [Int16](repeating: 0, count: expectedCells)
		data.withUnsafeBytes { rawBuffer in
			let bytes = rawBuffer.bindMemory(to: UInt8.self)
			for index in 0..<expectedCells {
				let byteOffset = index * 2
				let value = UInt16(bytes[byteOffset]) | (UInt16(bytes[byteOffset + 1]) << 8)
				output[index] = Int16(bitPattern: value)
			}
		}
		return output
	}

	private static func encodePageData(_ page: [Int16]) -> Data {
		var output = [UInt8](repeating: 0, count: page.count * 2)
		for index in page.indices {
			let value = UInt16(bitPattern: page[index])
			output[index * 2] = UInt8(value & 0x00FF)
			output[index * 2 + 1] = UInt8((value & 0xFF00) >> 8)
		}
		return Data(output)
	}

	private static let hgtSize = 3_601
	private static let downsampledSize = 1_201
	private static let srtmNoData = Int16.min
}

private struct EngineParameters {
	var txAltFeet: Double
	var rxAltFeet: Double
	var erpWatts: Double
	var radioClimate: Int32
	var polarization: Int32
	var confidence: Double
	var reliability: Double
	var radiusKilometers: Double
	var resolutionIppd: Int
}

private struct CoverageBounds {
	var north: Double
	var south: Double
	var east: Double
	var west: Double
}

private struct CoverageRaster {
	var width: Int
	var height: Int
	var signal: UnsafeBufferPointer<UInt8>
	var mask: UnsafeBufferPointer<UInt8>
	var bounds: CoverageBounds

	func hasCoverage(at index: Int) -> Bool {
		(mask[index] & 248) != 0
	}
}

private struct PreparedCoverageGrid {
	var width: Int
	var height: Int
	var values: [Double]
	var bounds: CoverageBounds
}
