//
//  TAKDataPackageGenerator.swift
//  Meshtastic
//
//  Created by niccellular 12/26/25
//

import Foundation
import OSLog
import UIKit

/// Generates TAK data packages (.zip) for configuring TAK clients
/// to connect to the Meshtastic TAK server
final class TAKDataPackageGenerator: @unchecked Sendable {

	static let shared = TAKDataPackageGenerator()

	private init() {}

	// MARK: - Data Package Generation

	/// Generate a TAK data package for TAK client configuration
	/// - Parameters:
	///   - serverHost: The server hostname/IP (default: 127.0.0.1 for localhost)
	///   - port: The server port
	///   - useTLS: Whether to use TLS (ssl) with mTLS or plain TCP
	///   - description: Description shown in TAK client
	///   - userCertName: Optional custom name for the user client certificate (without .p12 extension)
	/// - Returns: URL to the generated zip file, or nil if generation failed
	func generateDataPackage(
		serverHost: String = "127.0.0.1",
		port: Int,
		useTLS: Bool = true,
		description: String = "Meshtastic TAK Server",
		userCertName: String? = nil
	) -> URL? {
		let fileManager = FileManager.default

		// The certificates for this install: the client's identity and what it trusts. Issued
		// here if the server has never run.
		let certificates = TAKCertificateManager.shared
		let truststore: Data
		let clientP12: Data
		let password: String
		do {
			let issued = try certificates.ensureIssuedCertificates()
			guard let store = try certificates.truststoreForExport() else {
				Logger.tak.error("No truststore to export")
				return nil
			}
			truststore = store
			clientP12 = issued.clientP12
			password = issued.password
		} catch {
			Logger.tak.error("Could not get the certificates for the data package: \(error.localizedDescription)")
			return nil
		}

		// Create temporary directory for package contents
		let packageName = "Meshtastic_TAK_Server"
		let tempDir = fileManager.temporaryDirectory.appendingPathComponent(packageName)

		do {
			// Clean up any existing temp directory
			if fileManager.fileExists(atPath: tempDir.path) {
				try fileManager.removeItem(at: tempDir)
			}
			try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

			// The client certificate file, named for the device (made safe for a file name)
			let baseName = (userCertName ?? UIDevice.current.name)
				.replacingOccurrences(of: " ", with: "_")
				.replacingOccurrences(of: "'", with: "")
				.replacingOccurrences(of: "\"", with: "")
			let userClientCertFileName = "\(baseName).p12"

			// Generate preference file at package root (flat structure for TAK client compatibility)
			let prefFileName = "meshtastic-server.pref"
			let configPref = generateConfigPref(
				serverHost: serverHost,
				port: port,
				useTLS: useTLS,
				description: description,
				certificates: (fileName: userClientCertFileName, password: password)
			)
			let configPrefURL = tempDir.appendingPathComponent(prefFileName)
			try configPref.write(to: configPrefURL, atomically: true, encoding: .utf8)
			Logger.tak.debug("Created \(prefFileName)")

			// The certificates, only for TLS. The truststore holds certificates and no key.
			if useTLS {
				try truststore.write(to: tempDir.appendingPathComponent("truststore.p12"))
				try clientP12.write(to: tempDir.appendingPathComponent(userClientCertFileName))
				Logger.tak.debug("Created truststore.p12 and \(userClientCertFileName)")
			}

			// Generate manifest.xml at root level (not in subdirectory)
			let manifest = generateManifest(
				description: description,
				useTLS: useTLS,
				prefFileName: prefFileName,
				userClientCertFileName: userClientCertFileName
			)
			let manifestURL = tempDir.appendingPathComponent("manifest.xml")
			try manifest.write(to: manifestURL, atomically: true, encoding: .utf8)
			Logger.tak.debug("Created manifest.xml")

			// Create the zip file in Documents directory for better share sheet compatibility
			let zipFileName = "\(packageName).zip"
			guard let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
				Logger.tak.error("Could not get Documents directory")
				return nil
			}
			let zipURL = documentsDir.appendingPathComponent(zipFileName)

			// Remove existing zip if present
			if fileManager.fileExists(atPath: zipURL.path) {
				try fileManager.removeItem(at: zipURL)
			}

			// Create zip archive
			try createZipArchive(from: tempDir, to: zipURL)

			// Verify zip was created
			guard fileManager.fileExists(atPath: zipURL.path) else {
				Logger.tak.error("ZIP file was not created")
				return nil
			}

			// Cleanup temp directory
			try? fileManager.removeItem(at: tempDir)

			Logger.tak.info("Generated TAK data package: \(zipURL.path)")
			return zipURL

		} catch {
			Logger.tak.error("Failed to generate TAK data package: \(error.localizedDescription)")
			try? fileManager.removeItem(at: tempDir)
			return nil
		}
	}

	// MARK: - Pref File Generation (matches working TAK data package format)

	private func generateConfigPref(
		serverHost: String,
		port: Int,
		useTLS: Bool,
		description: String,
		certificates: (fileName: String, password: String)
	) -> String {
		let protocolType = useTLS ? "ssl" : "tcp"
		// One password on both files, made with the certificates.
		let serverPassword = certificates.password
		let clientPassword = certificates.password
		let userClientCertFileName = certificates.fileName

		if useTLS {
			// TLS mode with mTLS (mutual TLS with client certificate)
			return """
			<?xml version='1.0' encoding='ASCII' standalone='yes'?>
			<preferences>
			  <preference version="1" name="cot_streams">
			    <entry key="count" class="class java.lang.Integer">1</entry>
			    <entry key="description0" class="class java.lang.String">\(escapeXML(description))</entry>
			    <entry key="enabled0" class="class java.lang.Boolean">true</entry>
			    <entry key="connectString0" class="class java.lang.String">\(serverHost):\(port):\(protocolType)</entry>
			  </preference>
			  <preference version="1" name="com.atakmap.app_preferences">
			    <entry key="displayServerConnectionWidget" class="class java.lang.Boolean">true</entry>
			    <entry key="caLocation" class="class java.lang.String">cert/truststore.p12</entry>
			    <entry key="caPassword" class="class java.lang.String">\(serverPassword)</entry>
			    <entry key="certificateLocation" class="class java.lang.String">cert/\(userClientCertFileName)</entry>
			    <entry key="clientPassword" class="class java.lang.String">\(clientPassword)</entry>
			  </preference>
			</preferences>
			"""
		} else {
			// TCP mode - no certificates needed
			return """
			<?xml version='1.0' encoding='ASCII' standalone='yes'?>
			<preferences>
			  <preference version="1" name="cot_streams">
			    <entry key="count" class="class java.lang.Integer">1</entry>
			    <entry key="description0" class="class java.lang.String">\(escapeXML(description))</entry>
			    <entry key="enabled0" class="class java.lang.Boolean">true</entry>
			    <entry key="connectString0" class="class java.lang.String">\(serverHost):\(port):\(protocolType)</entry>
			  </preference>
			  <preference version="1" name="com.atakmap.app_preferences">
			    <entry key="displayServerConnectionWidget" class="class java.lang.Boolean">true</entry>
			  </preference>
			</preferences>
			"""
		}
	}

	// MARK: - Manifest Generation (matches working TAK data package format)

	private func generateManifest(
		description: String,
		useTLS: Bool,
		prefFileName: String,
		userClientCertFileName: String
	) -> String {
		let uid = UUID().uuidString

		if useTLS {
			// TLS mode with mTLS - includes truststore and user client certificate
			return """
			<MissionPackageManifest version="2">
			  <Configuration>
			    <Parameter name="uid" value="\(uid)"/>
			    <Parameter name="name" value="Meshtastic_TAK_Server"/>
			    <Parameter name="onReceiveDelete" value="true"/>
			  </Configuration>
			  <Contents>
			    <Content ignore="false" zipEntry="\(prefFileName)"/>
			    <Content ignore="false" zipEntry="truststore.p12"/>
			    <Content ignore="false" zipEntry="\(userClientCertFileName)"/>
			  </Contents>
			</MissionPackageManifest>
			"""
		} else {
			// TCP mode - just the pref file
			return """
			<MissionPackageManifest version="2">
			  <Configuration>
			    <Parameter name="uid" value="\(uid)"/>
			    <Parameter name="name" value="Meshtastic_TAK_Server"/>
			    <Parameter name="onReceiveDelete" value="true"/>
			  </Configuration>
			  <Contents>
			    <Content ignore="false" zipEntry="\(prefFileName)"/>
			  </Contents>
			</MissionPackageManifest>
			"""
		}
	}

	// MARK: - Helper Methods

	private func escapeXML(_ string: String) -> String {
		return string
			.replacingOccurrences(of: "&", with: "&amp;")
			.replacingOccurrences(of: "<", with: "&lt;")
			.replacingOccurrences(of: ">", with: "&gt;")
			.replacingOccurrences(of: "\"", with: "&quot;")
			.replacingOccurrences(of: "'", with: "&apos;")
	}

	// MARK: - ZIP Archive Creation

	/// Create a ZIP archive from a directory
	private func createZipArchive(from sourceDir: URL, to destinationURL: URL) throws {
		let fileManager = FileManager.default
		var copyError: Error?

		// Use NSFileCoordinator to create zip - this is the built-in approach on iOS
		var coordinatorError: NSError?
		let coordinator = NSFileCoordinator()

		Logger.tak.debug("Creating ZIP from: \(sourceDir.path)")

		coordinator.coordinate(
			readingItemAt: sourceDir,
			options: .forUploading,
			error: &coordinatorError
		) { zipURL in
			Logger.tak.debug("Coordinator provided ZIP at: \(zipURL.path)")
			do {
				// The coordinator creates a temporary zip, copy it to our destination
				if fileManager.fileExists(atPath: destinationURL.path) {
					try fileManager.removeItem(at: destinationURL)
				}
				try fileManager.copyItem(at: zipURL, to: destinationURL)
				Logger.tak.debug("Copied ZIP to: \(destinationURL.path)")
			} catch {
				Logger.tak.error("Failed to copy ZIP: \(error.localizedDescription)")
				copyError = error
			}
		}

		if let coordinatorError = coordinatorError {
			Logger.tak.error("Coordinator error: \(coordinatorError.localizedDescription)")
			throw coordinatorError
		}
		if let copyError = copyError {
			throw copyError
		}
	}
}
