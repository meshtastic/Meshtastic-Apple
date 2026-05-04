// MARK: Color+Brand
//
//  Color+Brand.swift
//  Meshtastic
//
//  Meshtastic brand color tokens derived from the official design standards.
//  https://raw.githubusercontent.com/meshtastic/design/refs/heads/master/standards/meshtastic_design_standards_latest.md
//
//  System color shadows (.primary, .secondary) ensure every existing
//  call-site picks up the branded palette with no per-file changes.

import SwiftUI

// MARK: - System Color Shadows

extension Color {

	/// Branded accent — shadows SwiftUI `Color.accentColor`
	/// Cobalt #2855A8 both modes
	static var accentColor: Color { Color("Colors/MeshtasticAccent") }

	/// Branded primary text — shadows SwiftUI `Color.primary`
	/// Neutral 700 #3D3E50 light / Neutral 50 #F5F6FA dark
	static let primary = Color("Colors/MeshtasticPrimary")

	/// Branded secondary — shadows SwiftUI `Color.secondary`
	/// Neutral 300 #B8BAC8 light / Neutral 600 #555668 dark
	static let secondary = Color("Colors/MeshtasticSecondary")

	/// Branded success green — shadows SwiftUI `Color.green`
	/// Green 600 #3FB86D light / Green 500 #67EA94 dark
	static let green = Color("Colors/MeshtasticSuccess")

	/// Branded warning amber — shadows SwiftUI `Color.orange`
	/// Warning #E8A33E both modes
	static let orange = Color("Colors/MeshtasticWarning")

	/// Branded error red — shadows SwiftUI `Color.red`
	/// Error #E05252 both modes
	static let red = Color("Colors/MeshtasticError")

	/// Branded blue — shadows SwiftUI `Color.blue`
	/// Info #5C6BC0 both modes
	static let blue = Color("Colors/MeshtasticInfo")
}
