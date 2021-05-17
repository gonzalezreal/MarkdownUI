import CommonMark
import Foundation

#if os(macOS)
    import AppKit
#elseif canImport(UIKit)
    import UIKit
#endif

final class AttributedStringRenderer {
    private struct State {
        var attributes: [NSAttributedString.Key: Any] = [:]
        var paragraph = ParagraphState()
    }

    private let writingDirection: NSWritingDirection
    private let alignment: NSTextAlignment
    private let style: MarkdownStyle

    #if !os(watchOS)
        private var attachments: [String: NSTextAttachment] = [:]
    #endif

    private var states: [State] = []
    private var state = State()

    init(writingDirection: NSWritingDirection, alignment: NSTextAlignment, style: MarkdownStyle) {
        self.writingDirection = writingDirection
        self.alignment = alignment
        self.style = style
    }

    #if !os(watchOS)
        func attributedString(for document: Document, attachments: [String: NSTextAttachment]) -> NSAttributedString {
            self.attachments = attachments

            states.removeAll()
            state = State(
                attributes: [
                    .font: style.font,
                    .foregroundColor: style.foregroundColor,
                ],
                paragraph: ParagraphState(
                    baseWritingDirection: writingDirection,
                    alignment: alignment
                )
            )

            style.documentAttributes(&state.attributes)
            return attributedString(for: document.blocks)
        }
    #else
        func attributedString(for document: Document) -> NSAttributedString {
            states.removeAll()
            state = State(
                attributes: [
                    .font: style.font,
                    .foregroundColor: style.foregroundColor,
                ],
                paragraph: ParagraphState(
                    baseWritingDirection: writingDirection,
                    alignment: alignment
                )
            )

            style.documentAttributes(&state.attributes)
            return attributedString(for: document.blocks)
        }
    #endif
}

private extension AttributedStringRenderer {
    enum Constants {
        static let lineSeparator = "\u{2028}"
        static let paragraphSeparator = "\u{2029}"
    }

    func attributedString(for blocks: [Block]) -> NSAttributedString {
        blocks
            .map { attributedString(for: $0) }
            .joined(separator: NSAttributedString(string: Constants.paragraphSeparator))
    }

    func attributedString(for block: Block) -> NSAttributedString {
        switch block {
        case let .blockQuote(blocks):
            saveState()
            defer { restoreState() }

            state.paragraph.indentLevel += 1
            style.blockQuoteAttributes(&state.attributes)

            return attributedString(for: blocks)

        case let .list(value):
            saveState()
            defer { restoreState() }

            state.paragraph.indentLevel += 1

            return attributedString(for: value)

        case let .code(value, _):
            saveState()
            defer { restoreState() }

            state.paragraph.indentLevel += 1
            style.codeBlockAttributes(&state.attributes, paragraphState: state.paragraph)

            let cleanCode = value.trimmingCharacters(in: CharacterSet.newlines)
                .components(separatedBy: CharacterSet.newlines)
                .joined(separator: Constants.lineSeparator)

            return NSAttributedString(string: String(cleanCode), attributes: state.attributes)

        case let .html(value):
            guard let data = value.data(using: .utf8) else {
                return NSAttributedString()
            }

            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ]
            var documentAttributes: NSDictionary? = [:]

            #if canImport(UIKit)
                let result = try? NSMutableAttributedString(data: data, options: options, documentAttributes: &documentAttributes)
            #elseif canImport(AppKit)
                let result = NSMutableAttributedString(html: data, options: options, documentAttributes: &documentAttributes)
            #endif

            if let result = result {
                saveState()
                defer { restoreState() }

                style.htmlBlockAttributes(&state.attributes, paragraphState: state.paragraph)
                result.addAttributes(state.attributes, range: NSRange(location: 0, length: result.length))

                return result
            } else {
                return NSAttributedString()
            }

        case let .paragraph(inlines):
            saveState()
            defer { restoreState() }

            style.paragraphAttributes(&state.attributes, paragraphState: state.paragraph)

            return attributedString(for: inlines)

        case let .heading(inlines, level):
            saveState()
            defer { restoreState() }

            style.headingAttributes(&state.attributes, level: level, paragraphState: state.paragraph)

            return attributedString(for: inlines)

        case .thematicBreak:
			let hr: NSAttributedString
			#if os(macOS)
			hr = NSAttributedString(string: "\u{00A0} \u{0009} \u{00A0}\n", attributes: [.strikethroughStyle: NSUnderlineStyle.single.rawValue, .strikethroughColor: NSColor.gray])
			#elseif os(iOS)
			hr = NSAttributedString(string: "\u{00A0} \u{0009} \u{00A0}\n", attributes: [.strikethroughStyle: NSUnderlineStyle.single.rawValue, .strikethroughColor: UIColor.gray])
			#else
			hr = NSAttributedString()
			#endif

			return hr
        }
    }

    func attributedString(for inlines: [Inline]) -> NSAttributedString {
        inlines
            .map { attributedString(for: $0) }
            .joined()
    }

    func attributedString(for inline: Inline) -> NSAttributedString {
        switch inline {
        case let .text(value):
            return NSAttributedString(string: value, attributes: state.attributes)

        case .softBreak:
            return NSAttributedString(string: " ", attributes: state.attributes)

        case .lineBreak:
            return NSAttributedString(string: Constants.lineSeparator, attributes: state.attributes)

        case let .code(value):
            saveState()
            defer { restoreState() }

            style.codeAttributes(&state.attributes)

            return NSAttributedString(string: value, attributes: state.attributes)

        case let .html(value):
            return NSAttributedString(string: value, attributes: state.attributes)

        case let .emphasis(inlines):
            saveState()
            defer { restoreState() }

            style.emphasisAttributes(&state.attributes)

            return attributedString(for: inlines)

        case let .strong(inlines):
            saveState()
            defer { restoreState() }

            style.strongAttributes(&state.attributes)

            return attributedString(for: inlines)

        case let .link(inlines, url, title):
            saveState()
            defer { restoreState() }

            style.linkAttributes(&state.attributes, url: url, title: title)

            return attributedString(for: inlines)

        case let .image(_, url, _):
            #if os(watchOS)
                return NSAttributedString()
            #else
                guard let attachment = attachments[url] else {
                    return NSAttributedString()
                }

                let result = NSMutableAttributedString(attachment: attachment)

                result.addAttributes(
                    state.attributes,
                    range: NSRange(location: 0, length: result.length)
                )

                return result
            #endif
        }
    }

    func attributedString(for list: List) -> NSAttributedString {
        saveState()
        defer { restoreState() }

        state.paragraph.spacing = list.spacing

        return list.items.enumerated().map { offset, item in
            attributedString(
                for: item,
                delimiter: list.delimiter(at: offset),
                isLastItem: offset == list.items.count - 1
            )
        }.joined(separator: NSAttributedString(string: Constants.paragraphSeparator))
    }

    func attributedString(for item: Item, delimiter: String, isLastItem: Bool) -> NSAttributedString {
        let delimiterBlock = Block.paragraph([.text(delimiter + "\t")])

        guard !item.blocks.isEmpty else {
            return attributedString(for: delimiterBlock)
        }

        return item.blocks.enumerated().map { offset, block in
            saveState()
            defer { restoreState() }

            if isLastItem, offset == item.blocks.count - 1 {
                state.paragraph.spacing = .loose
            }

            if offset == 0 {
                state.paragraph.isHanging = true

                return [
                    attributedString(for: delimiterBlock),
                    attributedString(for: block),
                ].joined()
            } else {
                state.paragraph.indentLevel += 1
                return attributedString(for: block)
            }
        }.joined(separator: NSAttributedString(string: Constants.paragraphSeparator))
    }

    func saveState() {
        states.append(state)
    }

    func restoreState() {
        state = states.removeLast()
    }
}

private extension List {
    func delimiter(at index: Int) -> String {
        switch style {
        case .bullet:
            return "\u{2022}"
        case let .ordered(start):
            return "\(start + index)."
        }
    }
}
