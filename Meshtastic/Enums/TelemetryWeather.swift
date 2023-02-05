//
//  TelemetryWeather.swift
//  Meshtastic
//
//  Copyright Garth Vander Houwen 2/4/23.
//

//https://developer.apple.com/documentation/weatherkit/weathercondition

// clear *
// cloudy *
// foggy
// haze
// mostlyClear
// partlyCloudy
// smoky *
// breezy
// windy
// drizzle
// heavyRain
// isolatedThunderstorms
// rain *
// sunShowers
// scatteredThunderstorms
// strongStorms
// thunderstorms
// frigid *
// hail
// hot *
// flurries
// sleet
// snow *
// sunFlurries
// wintryMix
// blizzard
// blowingSnow
// freezingDrizzle
// freezingRain
// heavySnow
// hurricane
// tropicalStorm

enum WeatherConditions: Int, CaseIterable, Identifiable {

	case clear = 0
	case cloudy = 1
	case frigid = 2
	case hot = 3
	case rain = 4
	case smoky = 5
	case snow = 6

	var id: Int { self.rawValue }
	var symbolName: String {
		get {
			switch self {
			
			case .clear:
				return "sparkle"
			case .cloudy:
				return "cloud"
			case .hot:
				return "sun.max.trianglebadge.exclamationmark.fill"
			case .rain:
				return "cloud.rain"
			case .frigid:
				return "thermometer.snowflake"
			case .smoky:
				return "smoke"
			case .snow:
				return "cloud.snow"
			}
		}
	}
}
