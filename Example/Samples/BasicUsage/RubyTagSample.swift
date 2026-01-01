//  Copyright © 2025 PRND. All rights reserved.

import SwiftUI
import SwiftUIHTML

struct RubyTagSample: View {
    private let html = """
        <p>Ruby annotation rendering:</p>
        <p>
            <ruby style="font-size: 20px; color: #1a4;">
                漢字<rt>かんじ</rt>
            </ruby>
            を読む
        </p>
        <p>
            <ruby>
                学校<rt>がっこう</rt>
            </ruby>
            へ行く
        </p>
        <p>
            <ruby ruby-position="after" ruby-scale="0.5">
                今日<rt>きょう</rt>
            </ruby>
            は晴れです
        </p>
        """

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ruby Annotations")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Basic <ruby>/<rt> support using CoreText")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Divider()

                HTMLView(html: html, parser: HTMLFuziParser())
                    .htmlEnvironment(\.configuration, .sample)
                    .htmlEnvironment(\.styleContainer, .sample(by: .byWordWrapping))
                    .padding()
                    .background(Color.platformSystemGray6)
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 8) {
                    Text("HTML")
                        .font(.headline)

                    Text(html)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .background(Color.platformSystemGray6)
                        .cornerRadius(8)
                }
            }
            .padding()
        }
        .navigationTitle("Ruby Tags")
        .applyInlineNavigationTitleDisplayMode()
    }
}

#Preview {
    NavigationView {
        RubyTagSample()
    }
}
