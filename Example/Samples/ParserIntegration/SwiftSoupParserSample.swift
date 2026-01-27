//  Copyright © 2026 PRND. All rights reserved.

#if canImport(SwiftSoup)
import SwiftUI
import SwiftUIHTML

struct SwiftSoupParserSample: View {
    private let html = """
    <div class="parser-sample">
        <h2>SwiftSoup Parser</h2>
        <p id="description">Parsed with <em>SwiftSoup</em> and converted to HTMLNode.</p>
        <p>Ruby: <ruby ruby-position="after">漢字<rt>かんじ</rt></ruby></p>
        <p>Line break<br>after br tag.</p>
    </div>
    """

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SwiftSoup Parser")
                .font(.title2)
                .fontWeight(.semibold)

            HTMLView(html: html, parser: HTMLSwiftSoupParser())
                .htmlEnvironment(\.configuration, .sample)
        }
        .padding()
        .navigationTitle("SwiftSoup Parser")
        .applyInlineNavigationTitleDisplayMode()
    }
}

#endif
