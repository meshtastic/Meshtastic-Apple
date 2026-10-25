//
//  CinemaContent.swift
//  CinemaContent
//
//  Copyright(c) Garth Vander Houwen 10/23/26.
//
import Foundation

/// The URL of a cinema environment's equirectangular image, by name.
public func cinemaEnvironmentImageURL(named name: String) -> URL? {
	Bundle.module.url(forResource: name, withExtension: "heic", subdirectory: "Environments")
}

/// Where the boards in a cinema environment's image sit, written by the render script next to
/// the image. See `scripts/cinema/README.md`.
public func cinemaEnvironmentAnchorsURL(named name: String) -> URL? {
	Bundle.module.url(forResource: "\(name)_anchors", withExtension: "json", subdirectory: "Environments")
}
