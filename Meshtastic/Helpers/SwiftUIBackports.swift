import SwiftUI
import CoreLocation
#if canImport(UIKit)
import UIKit
#endif

// Backport shims for running on iOS 15.4.1.
// These definitions intentionally no-op on platforms that lack the
// corresponding SwiftUI APIs while keeping the call-sites unchanged.

@available(iOS, introduced: 13, obsoleted: 16)
public struct PresentationDetent: Hashable {
    public static let large = PresentationDetent()
    public static let medium = PresentationDetent()
    public static func fraction(_ fraction: CGFloat) -> PresentationDetent { PresentationDetent() }
    public init() {}
}

@available(iOS, introduced: 13, obsoleted: 16)
public enum PresentationContentInteraction {
    case automatic
    case scrolls
    case resizes
}

@available(iOS, introduced: 13, obsoleted: 16)
public struct PresentationBackgroundInteraction: Hashable {
    public static let automatic = PresentationBackgroundInteraction()
    public static func enabled(upThrough detent: PresentationDetent) -> PresentationBackgroundInteraction { PresentationBackgroundInteraction() }
    public static let disabled = PresentationBackgroundInteraction()
    public init() {}
}

@available(iOS, introduced: 13, obsoleted: 16)
public enum PresentationCompactAdaptation {
    case automatic
    case popover
    case fullScreenCover
}

@available(iOS, introduced: 13, obsoleted: 16)
public extension View {
    func presentationDetents(_ detents: [PresentationDetent]) -> some View { self }
    func presentationDetents(_ detents: Set<PresentationDetent>) -> some View { self }
    func presentationDetents(_ detents: [PresentationDetent], selection: Binding<PresentationDetent?>) -> some View { self }
    func presentationDetents(_ detents: [PresentationDetent], selection: Binding<PresentationDetent>) -> some View { self }
    func presentationDetents(_ detents: Set<PresentationDetent>, selection: Binding<PresentationDetent?>) -> some View { self }
    func presentationDetents(_ detents: Set<PresentationDetent>, selection: Binding<PresentationDetent>) -> some View { self }
    func presentationContentInteraction(_ interaction: PresentationContentInteraction) -> some View { self }
    func presentationDragIndicator(_ visibility: Visibility) -> some View { self }
    func presentationBackgroundInteraction(_ interaction: PresentationBackgroundInteraction) -> some View { self }
    func presentationCompactAdaptation(_ adaptation: PresentationCompactAdaptation) -> some View { self }
}

@available(iOS, introduced: 13, obsoleted: 17)
public extension View {
    func onChangeBackport<Value: Equatable>(of value: Value, initial: Bool = false, _ action: @escaping (_ oldValue: Value, _ newValue: Value) -> Void) -> some View {
        modifier(OnChangeLegacyModifier(value: value, initial: initial, action: action))
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
public extension TextField where Label == Text {
    init(_ titleKey: LocalizedStringKey, text: Binding<String>, axis: Axis) {
        self.init(titleKey, text: text)
    }

    init<S>(_ title: S, text: Binding<String>, axis: Axis) where S : StringProtocol {
        self.init(title, text: text)
    }
}

public extension View {
    /// Conditionally applies a modifier produced by the closure when it returns a non-nil result.
    /// - Parameter transform: Closure that returns the modified view or `nil` to leave the original content untouched.
    func backportModify<Modified: View>(_ transform: (Self) -> Modified?) -> some View {
        if let modified = transform(self) {
            return AnyView(modified)
        } else {
            return AnyView(self)
        }
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
