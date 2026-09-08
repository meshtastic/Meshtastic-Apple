//
//  NodeSecurityIndicatorTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 9/7/26.
//

import Testing
@testable import Meshtastic

@Suite("NodeSecurityIndicator")
struct NodeSecurityIndicatorTests {

	@Test("2.8 and newer report signing support, older and unknown do not")
	func versionGate() {
		#expect(NodeSecurityIndicator.supportsSigning(firmwareVersion: "2.8"))   // DeviceMetadata truncates to two components
		#expect(NodeSecurityIndicator.supportsSigning(firmwareVersion: "2.8.0"))
		#expect(NodeSecurityIndicator.supportsSigning(firmwareVersion: "2.8.1"))
		#expect(NodeSecurityIndicator.supportsSigning(firmwareVersion: "2.10.0"))
		#expect(!NodeSecurityIndicator.supportsSigning(firmwareVersion: "2.7.26"))
		#expect(!NodeSecurityIndicator.supportsSigning(firmwareVersion: "2.5.14"))
		#expect(!NodeSecurityIndicator.supportsSigning(firmwareVersion: nil))
		#expect(!NodeSecurityIndicator.supportsSigning(firmwareVersion: ""))
	}

	@Test("2.8 nodes show signing state instead of the locks")
	func signingReplacesLocks() {
		#expect(NodeSecurityIndicator.status(firmwareVersion: "2.8.0", pkiEncrypted: true, keyMatch: true) == .signed)
		#expect(NodeSecurityIndicator.status(firmwareVersion: "2.8.0", pkiEncrypted: false, keyMatch: false) == .signed)
	}

	@Test("older nodes keep the locks")
	func olderNodesKeepLocks() {
		#expect(NodeSecurityIndicator.status(firmwareVersion: "2.7.26", pkiEncrypted: true, keyMatch: true) == .publicKey)
		#expect(NodeSecurityIndicator.status(firmwareVersion: "2.7.26", pkiEncrypted: false, keyMatch: false) == .sharedKey)
		#expect(NodeSecurityIndicator.status(firmwareVersion: nil, pkiEncrypted: true, keyMatch: true) == .publicKey)
	}

	@Test("a key mismatch is a warning at any version, even for a signed node")
	func mismatchAlwaysShows() {
		#expect(NodeSecurityIndicator.status(firmwareVersion: "2.8.0", pkiEncrypted: true, keyMatch: false) == .keyMismatch)
		#expect(NodeSecurityIndicator.status(firmwareVersion: "2.7.26", pkiEncrypted: true, keyMatch: false) == .keyMismatch)
	}

	@Test("the connected radio's own row shows verified on 2.8")
	func ownNodeIsVerified() {
		#expect(NodeSecurityIndicator.status(firmwareVersion: "2.8.0", pkiEncrypted: false, keyMatch: false, isOwnNode: true) == .verified)
		// Below 2.8 the own node keeps the locks like everything else.
		#expect(NodeSecurityIndicator.status(firmwareVersion: "2.7.26", pkiEncrypted: true, keyMatch: true, isOwnNode: true) == .publicKey)
	}

	@Test("an in-person verified contact outranks signing on 2.8")
	func verifiedOutranksSigned() {
		#expect(NodeSecurityIndicator.status(firmwareVersion: "2.8.0", pkiEncrypted: true, keyMatch: true, verified: true) == .verified)
		#expect(NodeSecurityIndicator.status(firmwareVersion: "2.8.0", pkiEncrypted: false, keyMatch: false, verified: true) == .verified)
		// Verification does not override a mismatch warning, and does not apply below 2.8.
		#expect(NodeSecurityIndicator.status(firmwareVersion: "2.8.0", pkiEncrypted: true, keyMatch: false, verified: true) == .keyMismatch)
		#expect(NodeSecurityIndicator.status(firmwareVersion: "2.7.26", pkiEncrypted: true, keyMatch: true, verified: true) == .publicKey)
	}
}
