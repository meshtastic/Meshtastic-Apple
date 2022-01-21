//
//  AppDelegate.swift
//  MeshtasticClient
//
//  Created by Joshua Pirihi on 16/01/22.
//

import Foundation
import UIKit

class MTAppDelegate: NSObject, UIApplicationDelegate {
	
	func applicationDidFinishLaunching(_ application: UIApplication) {
	}
	
  func application(
	_ application: UIApplication,
	didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
	// ...
	return true
  }
	
	func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
	  print("We received a file")
	  return true
	}
}
