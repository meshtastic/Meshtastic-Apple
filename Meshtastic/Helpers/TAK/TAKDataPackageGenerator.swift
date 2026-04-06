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
final class TAKDataPackageGenerator {

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

		// Create temporary directory for package contents
		let packageName = "Meshtastic_TAK_Server"
		let tempDir = fileManager.temporaryDirectory.appendingPathComponent(packageName)

		do {
			// Clean up any existing temp directory
			if fileManager.fileExists(atPath: tempDir.path) {
				try fileManager.removeItem(at: tempDir)
			}
			try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

			// Determine user client certificate filename
			let userClientCertFileName: String
			if let customName = userCertName {
				userClientCertFileName = "\(customName).p12"
			} else {
				// Use device name as default (sanitize for filename safety)
				let deviceName = UIDevice.current.name
					.replacingOccurrences(of: " ", with: "_")
					.replacingOccurrences(of: "'", with: "")
					.replacingOccurrences(of: "\"", with: "")
				userClientCertFileName = "\(deviceName).p12"
			}

			// Generate preference file at package root (flat structure for TAK client compatibility)
			let prefFileName = "meshtastic-server.pref"
			let configPref = generateConfigPref(
				serverHost: serverHost,
				port: port,
				useTLS: useTLS,
				description: description,
				userClientCertFileName: userClientCertFileName
			)
			let configPrefURL = tempDir.appendingPathComponent(prefFileName)
			try configPref.write(to: configPrefURL, atomically: true, encoding: .utf8)
			Logger.tak.debug("Created \(prefFileName)")

			// Copy certificates (only needed for TLS/mTLS mode)
			if useTLS {
				// Truststore (server cert for verifying server) - uses custom if available
				if let serverP12Data = TAKCertificateManager.shared.getActiveServerP12Data() {
					let truststoreURL = tempDir.appendingPathComponent("truststore.p12")
					try serverP12Data.write(to: truststoreURL)
					Logger.tak.debug("Created truststore.p12 (custom: \(TAKCertificateManager.shared.hasCustomServerCertificate()))")
				} else {
					Logger.tak.warning("No server certificate data available")
				}

				// User client certificate for mTLS - uses custom if available
				if let clientP12Data = TAKCertificateManager.shared.getActiveClientP12Data() {
					let clientURL = tempDir.appendingPathComponent(userClientCertFileName)
					try clientP12Data.write(to: clientURL)
					Logger.tak.debug("Created \(userClientCertFileName) (custom: \(TAKCertificateManager.shared.hasCustomClientP12()))")
				} else {
					Logger.tak.warning("No client certificate data available")
				}
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
		userClientCertFileName: String
	) -> String {
		let protocolType = useTLS ? "ssl" : "tcp"
		// Use active certificate passwords (custom if available, otherwise bundled)
		let serverPassword = TAKCertificateManager.shared.getActiveServerCertificatePassword()
		let clientPassword = TAKCertificateManager.shared.getActiveClientCertificatePassword()

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
