//
//  TVTheme.swift
//  Meshtastic TV
//
//  Copyright(c) Garth Vander Houwen 7/26/26.
//
//  Shared layout tokens for the tvOS app, so the recurring design-decision sizes
//  (side-list width, node-avatar diameters, screen padding, corner radius) live in
//  one place instead of being scattered as magic numbers across the views. Font
//  sizes use @ScaledMetric at their call sites so they stay Dynamic-Type aware.
//

import CoreGraphics

enum TVTheme {
	/// Node side-list column width on the map screen.
	static let sideListWidth: CGFloat = 520

	/// Horizontal inset that keeps focused node-list controls inside the List clip.
	static let nodeListContentMargin: CGFloat = 16

	/// Node avatar (circle) diameters.
	static let listAvatarSize: CGFloat = 56
	static let detailAvatarSize: CGFloat = 68

	/// Outer padding for a full detail panel.
	static let screenPadding: CGFloat = 40

	/// Horizontal inset for controls on the connect screen.
	static let connectHorizontalInset: CGFloat = 16

	/// Gap between sections in the node detail panel.
	static let sectionSpacing: CGFloat = 32

	/// Corner radius for the focusable detail rows.
	static let rowCornerRadius: CGFloat = 10

	/// Wordmark logo height in the map header.
	static let wordmarkHeight: CGFloat = 30

	/// Vertical margin for the mesh stats strip. The map is full-bleed
	/// (.ignoresSafeArea), so the strip supplies its own distance from the
	/// screen edge — kept tight so the strip hugs the edge it's pinned to.
	static let statsStripMargin: CGFloat = 24

	/// Mesh stats strip layout.
	static let statsStripColumnSpacing: CGFloat = 18
	static let statsStripMetricSpacing: CGFloat = 6
	static let statsStripPacketSpacing: CGFloat = 10
	static let statsStripEventWidth: CGFloat = 230
	static let statsStripEventLogoSize: CGFloat = 56
	static let statsStripNodesWidth: CGFloat = 200
	static let statsStripUtilizationWidth: CGFloat = 140
	static let statsStripHorizontalPadding: CGFloat = 36
	static let statsStripVerticalPadding: CGFloat = 28
	static let statsStripCornerRadius: CGFloat = 24
	static let statsStripDividerWidth: CGFloat = 1
	static let statsStripDividerHeight: CGFloat = 104
	static let statsStripMetadataHeight: CGFloat = 27.5
}
