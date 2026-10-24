//
//  CinemaContent.swift
//  CinemaContent
//
//  Copyright(c) Garth Vander Houwen 10/23/26.
//
import Foundation

/// The URL of a cinema environment's equirectangular image, by name.
public func cinemaEnvironmentImageURL(named name: String) -> URL? {
	Bundle.module.url(forResource: name, withExtension: "jpg", subdirectory: "Environments")
}
