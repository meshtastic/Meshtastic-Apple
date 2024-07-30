import Foundation

extension Date {
	func formattedDate(format: String) -> String {
		let dateformat = DateFormatter()
		dateformat.dateFormat = format

		if self > Calendar.current.date(byAdding: .year, value: -5, to: Date())! {
			return dateformat.string(from: self)
		}
		else {
			return "Unknown"
		}
	}

	func relativeTimeOfDay() -> String {
		let hour = Calendar.current.component(.hour, from: self)

		switch hour {
		case 6..<12:
			return "Morning"

		case 12:
			return "Noon"

		case 13..<17:
			return "Afternoon"

		case 17..<22:
			return "Evening"

		default:
			return "Night"
		}
	}

	func relative() -> String {
		let absoluteFormatter = DateFormatter()
		absoluteFormatter.dateStyle = .medium
		absoluteFormatter.timeStyle = .short

		let now = Date()

		let secondsAgo = Int(now.timeIntervalSince(self))

		if secondsAgo < 90 {
			return "Just now"
		}
		else if secondsAgo < 60 * 60 {
			let minutes = secondsAgo / 60
			return "\(minutes) minutes ago"
		}
		else if secondsAgo < 24 * 60 * 60 {
			let hours = secondsAgo / 3600
			return "\(hours) hours ago"
		}
		else if secondsAgo < 7 * 24 * 60 * 60 {
			let days = secondsAgo / 86400
			return "\(days) days ago"
		}
		else {
			return absoluteFormatter.string(from: self)
		}
	}
}
