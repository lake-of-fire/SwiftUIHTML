//  Copyright © 2025 PRND. All rights reserved.
#if os(iOS)
import XCTest

@testable import SwiftUIHTML
@testable import SwiftUIHTMLExample

@MainActor
final class HTMLBasicXCTest: XCTestCase {
    private let sut = HTMLBasicTests()

    func testTestingBasicHTMLElements_byWordWrapping() async throws {
        try await sut.testingBasicHTMLElements(lineBreakMode: .byWordWrapping)
    }

    func testTestingBasicHTMLElements_byCharWrapping() async throws {
        try await sut.testingBasicHTMLElements(lineBreakMode: .byCharWrapping)
    }

    func testTestingLineBreak_byCharWrapping() async throws {
        try await sut.testingLineBreak(lineBreakMode: .byCharWrapping)
    }

    func testTestingLineBreak_byWordWrapping() async throws {
        try await sut.testingLineBreak(lineBreakMode: .byWordWrapping)
    }

    func testHTMLImageAndNesting_375_byCharWrapping() async throws {
        try await sut.testHTMLImageAndNesting(width: 375, lineBreakMode: .byCharWrapping)
    }

    func testHTMLImageAndNesting_375_byWordWrapping() async throws {
        try await sut.testHTMLImageAndNesting(width: 375, lineBreakMode: .byWordWrapping)
    }

    func testHTMLImageWithLineHeight() async throws {
        try await sut.testHTMLImageWithLineHeight()
    }

    func testTestingStyleHTMLElements_byWordWrapping() async throws {
        try await sut.testingStyleHTMLElements(lineBreakMode: .byWordWrapping)
    }

    func testTestingStyleHTMLElements_byCharWrapping() async throws {
        try await sut.testingStyleHTMLElements(lineBreakMode: .byCharWrapping)
    }

    func testImagePositionAndLineHeight() async throws {
        try await sut.testImagePositionAndLineHeight()
    }

    func testNonEnglishTextWithImages() async throws {
        try await sut.testNonEnglishTextWithImages()
    }

    func testLongWordsWithImages_byWordWrapping() async throws {
        try await sut.testLongWordsWithImages(lineBreakMode: .byWordWrapping)
    }

    func testLongWordsWithImages_byCharWrapping() async throws {
        try await sut.testLongWordsWithImages(lineBreakMode: .byCharWrapping)
    }

    func testComplexImageLayout() async throws {
        try await sut.testComplexImageLayout()
    }

    func testTestingWordBrek() async throws {
        try await sut.testingWordBrek()
    }

    func testYomitanEntrySnapshot() async throws {
        try await sut.testYomitanEntrySnapshot()
    }

    func testRubyAnnotationSnapshot() async throws {
        try await sut.testRubyAnnotationSnapshot()
    }

    func testRubyAnnotationSnapshotVanilla() async throws {
        try await sut.testRubyAnnotationSnapshotVanilla()
    }

    func testMarginSquareSnapshot() async throws {
        try await sut.testMarginSquareSnapshot()
    }

    func testDoubleMarginSquares() async throws {
        try await sut.testDoubleMarginSquares()
    }

    func testListItemSquareSnapshot() async throws {
        try await sut.testListItemSquareSnapshot()
    }

    func testBulletImageAlignment() async throws {
        try await sut.testBulletImageAlignment()
    }
}
#endif
