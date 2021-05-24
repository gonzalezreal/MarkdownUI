#if canImport(Combine) && !os(watchOS)

import Combine
import CombineSchedulers
import CommonMark
import Foundation
import NetworkImage

#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@available(macOS 11.0, iOS 14.0, tvOS 14.0, *)
final class MarkdownRenderer: ObservableObject {
    struct Environment {
        static let `default` = Environment(
            textAttachments: textAttachments(for:baseURL:),
            scheduler: DispatchQueue.main.eraseToAnyScheduler()
        )

        let textAttachments: (Set<String>, URL?) -> AnyPublisher<[String: NSTextAttachment], Never>
        let scheduler: AnySchedulerOf<DispatchQueue>
    }

    @Published private(set) var attributedString: NSAttributedString

    init(
        document: Document,
        baseURL: URL?,
        writingDirection: NSWritingDirection,
        alignment: NSTextAlignment,
        style: MarkdownStyle,
        environment: Environment = .default
    ) {
        self.attributedString = NSAttributedString(
            document: document,
            writingDirection: writingDirection,
            alignment: alignment,
            style: style
        )

        let urls = document.imageURLs

        if !urls.isEmpty {
            environment.textAttachments(urls, baseURL)
                .map { attachments in
                    NSAttributedString(
                        document: document,
                        attachments: attachments,
                        writingDirection: writingDirection,
                        alignment: alignment,
                        style: style
                    )
                }
                .receive(on: environment.scheduler)
                .assign(to: &$attributedString)
        }
    }
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, *)
private func textAttachments(
    for urls: Set<String>,
    baseURL: URL?
) -> AnyPublisher<[String: NSTextAttachment], Never> {
    let attachmentURLs = urls.compactMap {
        URL(string: $0, relativeTo: baseURL)
    }

    guard !attachmentURLs.isEmpty else {
        return Just([:]).eraseToAnyPublisher()
    }

    let textAttachmentPairs = attachmentURLs.map { publisher(for: $0) }

    return Publishers.MergeMany(textAttachmentPairs)
        .collect()
        .map { Dictionary($0, uniquingKeysWith: { _, last in last }) }
        .replaceError(with: [:])
        .eraseToAnyPublisher()
}


public extension OSImage {
    static func load(named name: String, in bundle: Bundle = .main) -> OSImage? {
        #if os(macOS)
        bundle.image(forResource: name)
        #else
        UIImage(named: name, in: bundle, compatibleWith: nil)
        #endif
    }
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, *)
private func publisher(for url: URL) -> AnyPublisher<(String, NSTextAttachment), Error> {
    if let publisher = localImageResourcePublisher(url: url) {
        return publisher
    }
    return ImageDownloader.shared.image(for: url).map { image -> (String, NSTextAttachment) in
        let attachment = ImageAttachment()
        attachment.image = image
        return (url.relativeString, attachment)
    }
    .eraseToAnyPublisher()
}

/// Publishes a local image resource when the URL scheme is `resource`.
/// - Parameter url: A URL such as `resource:///imagename`, which loads an image asset from the main bundle.
/// To load the image asset from a specific bundle, insert its identifier in the URL's host name,
/// for example `resource://org.vendor.bundle/imagename`.
/// - Returns: If an image asset exists, a publisher for it, `nil` otherwise.
@available(macOS 10.15, iOS 13.0, tvOS 13.0, *)
func localImageResourcePublisher(url: URL) -> AnyPublisher<(String, NSTextAttachment), Error>? {
    guard url.scheme == URL.mainBundleResources.scheme else { return nil }

    let name = NSString(string: url.path).lastPathComponent
    let bundle = url.host.flatMap(Bundle.init(identifier:)) ?? .main

    guard let image = OSImage.load(named: name, in: bundle) else { return nil }

    let attachment = ImageAttachment()
    attachment.image = image

    return Just((url.relativeString, attachment))
        .setFailureType(to: Error.self)
        .eraseToAnyPublisher()
}
#endif
