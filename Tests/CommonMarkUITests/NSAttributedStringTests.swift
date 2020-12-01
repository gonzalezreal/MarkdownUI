@testable import CommonMarkUI
import Foundation
import SnapshotTesting
import XCTest

final class NSAttributedStringTests: XCTestCase {
    private let configuration = NSAttributedString.Configuration(
        font: .custom("Helvetica", size: 16),
        paragraphStyle: .default
    )

    #if os(macOS)
        private let platformName = "AppKit"
    #elseif os(iOS) || os(tvOS) || os(watchOS)
        private let platformName = "UIKit"
    #endif

    func testParagraph() {
        let document = Document(
            #"""
            The sky above the port was the color of television, tuned to a dead channel.

            It was a bright cold day in April, and the clocks were striking thirteen.
            """#
        )!

        let attributedString = NSAttributedString(document: document, configuration: configuration)

        assertSnapshot(matching: attributedString, as: .dump, named: platformName)
    }
}