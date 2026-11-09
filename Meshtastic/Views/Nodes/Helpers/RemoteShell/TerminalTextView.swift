//
//  TerminalTextView.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/8/26.
//

import SwiftUI
import UIKit

/// What the terminal draws: the screen, the predicted echo after the cursor, and the cursor.
struct TerminalContent: Equatable {
	var lines: [[TerminalScreen.Cell]]
	var cursorColumn: Int
	var revision: Int
	var sentPrediction: String
	var unsentPrediction: String
	var showsCursor: Bool
}

/// Key events from the terminal, for the session.
struct TerminalInputHandlers {
	var text: (String) -> Void
	var backspace: () -> Void
	var key: (TerminalKey) -> Void
	var chord: (Character, _ control: Bool, _ alt: Bool) -> Void
	var paste: (String) -> Void
	var size: (_ cols: Int, _ rows: Int) -> Void
	/// A tap on the output.
	var tapped: () -> Void
	/// Pinching the output, with the scale since the pinch began.
	var pinch: (_ scale: CGFloat, _ ended: Bool) -> Void
}

/// The terminal's output in a scrolling, selectable text view, with a hidden view that takes
/// keyboard input. Scrolling follows new output only while the reader is at the bottom.
struct TerminalTextView: UIViewRepresentable {
	let content: TerminalContent
	let fontSize: CGFloat
	/// Whether typing goes to the terminal (character mode) rather than a composer.
	let takesKeyboard: Bool
	let handlers: TerminalInputHandlers

	func makeUIView(context: Context) -> TerminalContainerView {
		let view = TerminalContainerView()
		view.handlers = handlers
		return view
	}

	func updateUIView(_ view: TerminalContainerView, context: Context) {
		view.handlers = handlers
		view.takesKeyboard = takesKeyboard
		view.update(content: content, fontSize: fontSize)
	}
}

final class TerminalContainerView: UIView, UITextViewDelegate {
	let textView = UITextView()
	let keyInput = TerminalKeyInputView()
	var handlers: TerminalInputHandlers? {
		didSet { keyInput.handlers = handlers }
	}
	var takesKeyboard = true {
		didSet {
			guard takesKeyboard != oldValue else { return }
			if takesKeyboard {
				focusKeyboard()
			} else {
				keyInput.resignFirstResponder()
			}
		}
	}

	private var content: TerminalContent?
	private var drawnContent: TerminalContent?
	private var fontSize: CGFloat = 13
	private var drawnFont: UIFont?
	private var reportedSize: (cols: Int, rows: Int)?
	/// The size is reported once the pinch ends, so the node gets one resize, not one per step.
	private var pinching = false

	override init(frame: CGRect) {
		super.init(frame: frame)
		backgroundColor = .systemBackground
		textView.isEditable = false
		textView.isSelectable = true
		textView.backgroundColor = .systemBackground
		textView.textContainerInset = UIEdgeInsets(top: 8, left: 6, bottom: 8, right: 6)
		textView.alwaysBounceVertical = true
		textView.dataDetectorTypes = []
		textView.delegate = self
		textView.accessibilityLabel = String(localized: "Terminal output")
		textView.translatesAutoresizingMaskIntoConstraints = false
		keyInput.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
		keyInput.alpha = 0.01
		addSubview(keyInput)
		addSubview(textView)
		NSLayoutConstraint.activate([
			textView.leadingAnchor.constraint(equalTo: leadingAnchor),
			textView.trailingAnchor.constraint(equalTo: trailingAnchor),
			textView.topAnchor.constraint(equalTo: topAnchor),
			textView.bottomAnchor.constraint(equalTo: bottomAnchor)
		])
		let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
		textView.addGestureRecognizer(tap)
		textView.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:))))
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func didMoveToWindow() {
		super.didMoveToWindow()
		if window != nil, takesKeyboard {
			DispatchQueue.main.async { [weak self] in self?.focusKeyboard() }
		}
	}

	@objc private func tapped() {
		handlers?.tapped()
		if takesKeyboard { focusKeyboard() }
	}

	@objc private func pinched(_ recognizer: UIPinchGestureRecognizer) {
		switch recognizer.state {
		case .began, .changed:
			pinching = true
			handlers?.pinch(recognizer.scale, false)
		case .ended, .cancelled, .failed:
			handlers?.pinch(recognizer.scale, true)
			pinching = false
			setNeedsLayout()
		default:
			break
		}
	}

	func focusKeyboard() {
		guard window != nil else { return }
		keyInput.becomeFirstResponder()
	}

	override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
		super.traitCollectionDidChange(previousTraitCollection)
		drawnContent = nil
		if let content { update(content: content, fontSize: fontSize) }
	}

	override func layoutSubviews() {
		super.layoutSubviews()
		reportSize()
	}

	private var font: UIFont {
		let scaled = UIFontMetrics(forTextStyle: .body).scaledValue(for: fontSize, compatibleWith: traitCollection)
		return .monospacedSystemFont(ofSize: scaled, weight: .regular)
	}

	private func reportSize() {
		guard !pinching else { return }
		let font = self.font
		let inset = textView.textContainerInset
		let padding = textView.textContainer.lineFragmentPadding * 2
		let width = textView.bounds.width - inset.left - inset.right - padding
		let height = textView.bounds.height - inset.top - inset.bottom
		guard width > 0, height > 0 else { return }
		let cell = ("M" as NSString).size(withAttributes: [.font: font])
		let cols = Int(width / cell.width)
		let rows = Int(height / font.lineHeight)
		if let reportedSize, reportedSize == (cols, rows) { return }
		reportedSize = (cols, rows)
		handlers?.size(cols, rows)
	}

	func update(content: TerminalContent, fontSize: CGFloat) {
		self.content = content
		let sizeChanged = fontSize != self.fontSize
		self.fontSize = fontSize
		if sizeChanged {
			drawnContent = nil
			reportedSize = nil
			setNeedsLayout()
		}
		// Redrawing replaces the selection, so wait while the reader is selecting text.
		guard textView.selectedRange.length == 0 else { return }
		guard content != drawnContent || drawnFont != font else { return }
		draw(content)
	}

	func textViewDidChangeSelection(_ textView: UITextView) {
		if textView.selectedRange.length == 0, let content, content != drawnContent {
			draw(content)
		}
	}

	private func draw(_ content: TerminalContent) {
		let font = self.font
		let wasAtBottom = textView.contentOffset.y + textView.bounds.height >= textView.contentSize.height - font.lineHeight
		let offset = textView.contentOffset
		textView.attributedText = TerminalRenderer.attributedText(content, font: font, traits: traitCollection)
		drawnContent = content
		drawnFont = font
		textView.layoutIfNeeded()
		if wasAtBottom {
			let bottom = max(textView.contentSize.height - textView.bounds.height + textView.adjustedContentInset.bottom, -textView.adjustedContentInset.top)
			textView.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
		} else {
			textView.setContentOffset(offset, animated: false)
		}
	}

	/// The whole output as plain text, for Copy All.
	var plainText: String {
		textView.text ?? ""
	}
}

enum TerminalRenderer {
	static func attributedText(_ content: TerminalContent, font: UIFont, traits: UITraitCollection) -> NSAttributedString {
		let theme = Theme(
			isDark: traits.userInterfaceStyle == .dark,
			text: UIColor.label.resolvedColor(with: traits),
			background: UIColor.systemBackground.resolvedColor(with: traits),
			fonts: Fonts(font)
		)
		let paragraph = NSMutableParagraphStyle()
		paragraph.lineBreakMode = .byCharWrapping
		let result = NSMutableAttributedString()

		for (index, line) in content.lines.enumerated() {
			if index > 0 {
				result.append(NSAttributedString(string: "\n", attributes: [.font: font]))
			}
			if index == content.lines.count - 1 {
				appendCursorLine(line, content: content, into: result, theme: theme)
			} else {
				for run in TerminalScreen.runs(line) {
					result.append(NSAttributedString(string: run.text, attributes: attributes(run.style, theme: theme)))
				}
			}
		}
		result.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: result.length))
		return result
	}

	private static func appendCursorLine(
		_ line: [TerminalScreen.Cell],
		content: TerminalContent,
		into result: NSMutableAttributedString,
		theme: Theme
	) {
		var cells = line.map { (cell: $0, prediction: 0) }
		var column = content.cursorColumn
		let predictions = content.sentPrediction.map { ($0, 1) } + content.unsentPrediction.map { ($0, 2) }
		for (character, kind) in predictions {
			let cell = (cell: TerminalScreen.Cell(character: character, style: .plain), prediction: kind)
			while cells.count < column { cells.append((TerminalScreen.Cell(character: " ", style: .plain), 0)) }
			if column < cells.count { cells[column] = cell } else { cells.append(cell) }
			column += 1
		}
		if content.showsCursor, column >= cells.count {
			while cells.count <= column { cells.append((TerminalScreen.Cell(character: " ", style: .plain), 0)) }
		}
		for (index, entry) in cells.enumerated() {
			var attributes = attributes(entry.cell.style, theme: theme)
			if entry.prediction > 0 {
				// Typed but not yet echoed by the node.
				attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
				if entry.prediction == 2 {
					attributes[.foregroundColor] = theme.text.withAlphaComponent(0.45)
				}
			}
			if content.showsCursor, index == column {
				attributes[.backgroundColor] = theme.text
				attributes[.foregroundColor] = theme.background
			}
			result.append(NSAttributedString(string: String(entry.cell.character), attributes: attributes))
		}
	}

	private struct Theme {
		let isDark: Bool
		let text: UIColor
		let background: UIColor
		let fonts: Fonts
	}

	private struct Fonts {
		let regular: UIFont
		let bold: UIFont
		let italic: UIFont
		let boldItalic: UIFont

		init(_ font: UIFont) {
			regular = font
			bold = .monospacedSystemFont(ofSize: font.pointSize, weight: .bold)
			italic = font.fontDescriptor.withSymbolicTraits(.traitItalic).map { UIFont(descriptor: $0, size: font.pointSize) } ?? font
			boldItalic = bold.fontDescriptor.withSymbolicTraits([.traitBold, .traitItalic]).map { UIFont(descriptor: $0, size: font.pointSize) } ?? bold
		}
	}

	private static func attributes(_ style: TerminalStyle, theme: Theme) -> [NSAttributedString.Key: Any] {
		let isDark = theme.isDark, text = theme.text, background = theme.background, fonts = theme.fonts
		var foreground = style.foreground.map { TerminalPalette.color(boldBright($0, style.bold), dark: isDark) } ?? text
		var fill = style.background.map { TerminalPalette.color($0, dark: isDark) }
		if style.inverse {
			let swapped = fill ?? background
			fill = foreground
			foreground = swapped
		}
		foreground = TerminalPalette.legible(foreground, on: fill ?? background, text: (fill.map { TerminalPalette.luminance($0) < 0.5 } ?? isDark) ? .white : .black)
		if style.dim {
			foreground = TerminalPalette.dimmed(foreground, on: fill ?? background)
		}
		var attributes: [NSAttributedString.Key: Any] = [
			.font: style.bold ? (style.italic ? fonts.boldItalic : fonts.bold) : (style.italic ? fonts.italic : fonts.regular),
			.foregroundColor: foreground
		]
		if let fill {
			attributes[.backgroundColor] = fill
		}
		if style.underline {
			attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
		}
		return attributes
	}

	/// Bold brightens the first eight colors, as terminals do.
	private static func boldBright(_ color: TerminalColor, _ bold: Bool) -> TerminalColor {
		if bold, case let .ansi(index) = color, index < 8 {
			return .ansi(index + 8)
		}
		return color
	}
}

/// Takes keys for the terminal: typing, Backspace and Return from the on-screen keyboard, and
/// arrows, Escape, Tab and Control or Option chords from a hardware keyboard.
final class TerminalKeyInputView: UIView, UIKeyInput {
	var handlers: TerminalInputHandlers?

	var autocorrectionType: UITextAutocorrectionType = .no
	var autocapitalizationType: UITextAutocapitalizationType = .none
	var spellCheckingType: UITextSpellCheckingType = .no
	var smartQuotesType: UITextSmartQuotesType = .no
	var smartDashesType: UITextSmartDashesType = .no
	var smartInsertDeleteType: UITextSmartInsertDeleteType = .no
	var keyboardType: UIKeyboardType = .asciiCapable
	var inlinePredictionType: UITextInlinePredictionType = .no

	override var canBecomeFirstResponder: Bool { true }
	var hasText: Bool { true }

	func insertText(_ text: String) {
		handlers?.text(text)
	}

	func deleteBackward() {
		handlers?.backspace()
	}

	override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
		action == #selector(paste(_:)) ? UIPasteboard.general.hasStrings : super.canPerformAction(action, withSender: sender)
	}

	override func paste(_ sender: Any?) {
		if let text = UIPasteboard.general.string {
			handlers?.paste(text)
		}
	}

	override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
		var unhandled = Set<UIPress>()
		for press in presses {
			guard let key = press.key, handle(key) else {
				unhandled.insert(press)
				continue
			}
		}
		if !unhandled.isEmpty {
			super.pressesBegan(unhandled, with: event)
		}
	}

	private func handle(_ key: UIKey) -> Bool {
		let named: TerminalKey? = switch key.keyCode {
		case .keyboardUpArrow: .up
		case .keyboardDownArrow: .down
		case .keyboardLeftArrow: .left
		case .keyboardRightArrow: .right
		case .keyboardHome: .home
		case .keyboardEnd: .end
		case .keyboardPageUp: .pageUp
		case .keyboardPageDown: .pageDown
		case .keyboardEscape: .escape
		case .keyboardTab: .tab
		case .keyboardDeleteForward: .delete
		default: nil
		}
		if let named {
			handlers?.key(named)
			return true
		}
		let control = key.modifierFlags.contains(.control)
		let alt = key.modifierFlags.contains(.alternate)
		guard control || alt, !key.modifierFlags.contains(.command),
			  let character = key.charactersIgnoringModifiers.first else { return false }
		// On many layouts Option types ASCII the keycaps lack (`@`, `|`, `{`, `~`); let that
		// through as text. Option characters outside ASCII, as on a US layout, stay Meta.
		if alt, !control, let typed = key.characters.first, typed != character, typed.isASCII, !typed.isWhitespace {
			return false
		}
		handlers?.chord(character, control, alt)
		return true
	}
}
