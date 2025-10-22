import SwiftUI

#if !canImport(TipKit)
public protocol Tip {
    var id: String { get }
    var title: Text { get }
    var message: Text? { get }
    var image: Image? { get }
}

public enum Tips {
    public struct Configuration: Hashable {
        fileprivate init() {}
        public static func datastoreLocation(_ location: DatastoreLocation) -> Configuration { Configuration() }
        public static func displayFrequency(_ frequency: DisplayFrequency) -> Configuration { Configuration() }
    }

    public enum DatastoreLocation {
        case applicationDefault
    }

    public enum DisplayFrequency {
        case immediate
    }

    public static func resetDatastore() throws {}
    public static func configure(_ configuration: [Configuration]) throws {}
}

public struct TipViewStyleConfiguration {
    public var image: Image?
    public var title: Text?
    public var message: Text?

    public init(image: Image? = nil, title: Text? = nil, message: Text? = nil) {
        self.image = image
        self.title = title
        self.message = message
    }
}

public protocol TipViewStyle {
    associatedtype Body: View
    typealias Configuration = TipViewStyleConfiguration
    @ViewBuilder func makeBody(configuration: Configuration) -> Body
}

public struct TipView<T: Tip>: View {
    public init(_ tip: T, arrowEdge: Edge = .bottom) {}
    public var body: some View { EmptyView() }
}

public extension View {
    func tipViewStyle<S: TipViewStyle>(_ style: S) -> some View { self }
}

public struct PersistentTip: TipViewStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        EmptyView()
    }
}
#endif
