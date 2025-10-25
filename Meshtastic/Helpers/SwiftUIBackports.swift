import UIKit
import SwiftUI
import CoreLocation
import SwiftUIBackports


@available(iOS, introduced: 13, obsoleted: 16)
public enum PresentationCompactAdaptation {
    case automatic
    case popover
    case fullScreenCover
}

public extension Backport where Wrapped: View {
    @ViewBuilder
    func onChange<Value: Equatable>(of value: Value, initial: Bool = false, _ action: @escaping (_ oldValue: Value, _ newValue: Value) -> Void) -> some View {
        self.wrapped.modifier(OnChangeLegacyModifier(value: value, initial: initial, action: action))
    }

    @ViewBuilder
	func leadingListRowSeparatorAligned() -> some View {
		if #available(iOS 16, *) {
			self.wrapped.alignmentGuide(.listRowSeparatorLeading) { dimensions in
				dimensions[.leading]
			}
		} else {
			self.wrapped
		}
	}

    func apply<Modified: View>(_ transform: (Wrapped) -> Modified?) -> some View {
        if let modified = transform(self.wrapped) {
            return AnyView(modified)
        } else {
            return AnyView(self.wrapped)
        }
    }

    func defaultScrollAnchor(_ anchor: UnitPoint) -> some View { 
        if #available(iOS 17, *) {
            return AnyView(self.wrapped.defaultScrollAnchor(anchor))
        } else {
            return AnyView(self.wrapped)
        }
    }

    func presentationCompactAdaptation(_ adaptation: PresentationCompactAdaptation) -> some View {
        if #available(iOS 16.4, *) {
            switch adaptation {
            case .automatic:
                return AnyView(self.wrapped.presentationCompactAdaptation(.automatic))
            case .popover:
                return AnyView(self.wrapped.presentationCompactAdaptation(.popover))
            case .fullScreenCover:
                return AnyView(self.wrapped.presentationCompactAdaptation(.fullScreenCover))
            }
        } else {
            return AnyView(self.wrapped)
        }
    }

}

public extension Backport where Wrapped == Any {
    @available(iOS, introduced: 13, obsoleted: 17)
    struct ContentUnavailableView: View {
        private enum ImageSource {
            case system(String)
            case custom(AnyView)
        }

        private let title: Text
        private let description: Text?
        private let imageSource: ImageSource?

        public init(_ titleKey: LocalizedStringKey, systemImage: String, description: Text? = nil) {
            self.title = Text(titleKey)
            self.description = description
            self.imageSource = .system(systemImage)
        }

        public init<S>(_ title: S, systemImage: String, description: Text? = nil) where S: StringProtocol {
            self.title = Text(title)
            self.description = description
            self.imageSource = .system(systemImage)
        }

        public init(_ title: Text, systemImage: String, description: Text? = nil) {
            self.title = title
            self.description = description
            self.imageSource = .system(systemImage)
        }

        public init(_ titleKey: LocalizedStringKey, image: Image, description: Text? = nil) {
            self.title = Text(titleKey)
            self.description = description
            self.imageSource = .custom(AnyView(image))
        }

        public init<S>(_ title: S, image: Image, description: Text? = nil) where S: StringProtocol {
            self.title = Text(title)
            self.description = description
            self.imageSource = .custom(AnyView(image))
        }

        public init(_ title: Text, image: Image, description: Text? = nil) {
            self.title = title
            self.description = description
            self.imageSource = .custom(AnyView(image))
        }

        public var body: some View {
            VStack(spacing: 12) {
                if let imageSource {
                    imageView(for: imageSource)
                }

                title
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)

                if let description {
                    description
                        .font(.subheadline)
                        .foregroundColor(Color.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .accessibilityElement(children: .combine)
        }

        @ViewBuilder
        private func imageView(for source: ImageSource) -> some View {
            switch source {
            case .system(let name):
                Image(systemName: name)
                    .font(.system(size: 52, weight: .regular))
                    .foregroundColor(Color.secondary)
            case .custom(let view):
                view
                    .frame(maxWidth: 80, maxHeight: 80)
            }
        }
    }
}

private struct OnChangeLegacyModifier<Value: Equatable>: ViewModifier {
    let value: Value
    let initial: Bool
    let action: (_ oldValue: Value, _ newValue: Value) -> Void

    @State private var previousValue: Value?
    @State private var didTriggerInitial = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                if initial && !didTriggerInitial {
                    previousValue = value
                    action(value, value)
                    didTriggerInitial = true
                }
            }
            .onChange(of: value) { newValue in
                let oldValue = previousValue ?? newValue
                previousValue = newValue
                if !didTriggerInitial {
                    if initial {
                        action(oldValue, newValue)
                    }
                    didTriggerInitial = true
                } else {
                    action(oldValue, newValue)
                }
            }
    }
}

@available(iOS, introduced: 13, obsoleted: 16)
public extension Backport<Any>.PresentationDetent {
    static func fraction(_ fraction: CGFloat) -> Backport<Any>.PresentationDetent {
        if fraction > 0.5 {
            return .large
        } else {
            return .medium
        }
    }
}

@available(iOS, introduced: 13, obsoleted: 16)
public extension Backport<Any>.ToolbarItemPlacement {
    static var navigationBarTrailing: Backport<Any>.ToolbarItemPlacement {
        return .automatic
    }
}

@available(iOS, introduced: 13, obsoleted: 16)
public extension TextField where Label == Text {
    init(_ titleKey: LocalizedStringKey, text: Binding<String>, axis: Axis) {
        self.init(titleKey, text: text)
    }

    init<S>(_ title: S, text: Binding<String>, axis: Axis) where S : StringProtocol {
        self.init(title, text: text)
    }
}

public struct ColorComponentsCompat {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let opacity: Double
}

public extension Color {
    /// Resolves a SwiftUI `Color` into sRGB components across iOS versions.
    func resolvedComponents(in environment: EnvironmentValues) -> ColorComponentsCompat {
        if #available(iOS 17.0, *) {
            let resolved = self.resolve(in: environment)
            return ColorComponentsCompat(
                red: Double(resolved.red),
                green: Double(resolved.green),
                blue: Double(resolved.blue),
                opacity: Double(resolved.opacity)
            )
        } else {
            #if canImport(UIKit)
            let traitCollection = UITraitCollection(userInterfaceStyle: environment.colorScheme == .dark ? .dark : .light)
            let uiColor = UIColor(self).resolvedColor(with: traitCollection)

            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0

            if !uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha),
               let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
               let converted = uiColor.cgColor.converted(to: sRGB, intent: .relativeColorimetric, options: nil),
               let components = converted.components,
               components.count >= 3 {
                red = components[0]
                green = components[1]
                blue = components[2]
                alpha = components.count > 3 ? components[3] : 1
            }

            return ColorComponentsCompat(
                red: Double(red),
                green: Double(green),
                blue: Double(blue),
                opacity: Double(alpha)
            )
            #else
            return ColorComponentsCompat(red: 0, green: 0, blue: 0, opacity: 0)
            #endif
        }
    }
}

public extension CLLocationManager {
    /// Starts a background activity session when available on the current platform.
    func startBackgroundActivitySessionCompat() -> AnyObject? {
        if #available(iOS 17.0, *) {
            return CLBackgroundActivitySession()
        }
        return nil
    }

    /// Invalidates a previously created background session when supported.
    func invalidateBackgroundActivitySessionCompat(_ session: AnyObject?) {
        if #available(iOS 17.0, *) {
            (session as? CLBackgroundActivitySession)?.invalidate()
        }
    }
}

// Compat helpers for Task sleep APIs that require iOS 16+.
extension Task where Success == Never, Failure == Never {
    /// Sleeps for the specified number of seconds while remaining compatible with iOS 15.
    static func sleepBackport(seconds: Double) async throws {
        let clampedSeconds = max(seconds, 0)
        if #available(iOS 16.0, *) {
            try await sleep(for: .seconds(clampedSeconds))
        } else {
            let nanoseconds = UInt64(clampedSeconds * 1_000_000_000)
            try await sleep(nanoseconds: nanoseconds)
        }
    }
}