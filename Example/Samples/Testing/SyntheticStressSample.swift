//  Copyright © 2025 PRND. All rights reserved.

import SwiftUI
import SwiftUIHTML

struct SyntheticStressSample: View {
    @State private var sectionCount: Int = 12
    @State private var includeMedia: Bool = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Synthetic Stress Sample")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Generates large HTML that exercises most tags and styles.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Sections: \(sectionCount)")
                        Spacer()
                    }
                    .font(.headline)

                    Slider(value: Binding(
                        get: { Double(sectionCount) },
                        set: { sectionCount = Int($0) }
                    ), in: 4...30, step: 1)

                    Toggle("Include media (img/video)", isOn: $includeMedia)
                }
                .padding()
                .background(Color.platformSystemGray6)
                .cornerRadius(8)

                HTMLView(html: syntheticHTML(sectionCount: sectionCount, includeMedia: includeMedia), parser: HTMLFuziParser())
                    .htmlEnvironment(\.configuration, .sample)
                    .htmlEnvironment(\.styleContainer, .sample(by: .byWordWrapping))
                    .padding()
                    .background(Color.platformSystemGray6)
                    .cornerRadius(8)
            }
            .padding()
        }
        .navigationTitle("Synthetic Stress")
        .applyInlineNavigationTitleDisplayMode()
    }
}

private extension SyntheticStressSample {
    func syntheticHTML(sectionCount: Int, includeMedia: Bool) -> String {
        var chunks: [String] = []
        chunks.reserveCapacity(sectionCount * 6)

        chunks.append("""
            <body style="margin: 0; padding: 0;">
                <header style="background-color: #f0f0f0; padding: 16px; border-radius: 8px; margin-bottom: 12px;">
                    <h1 style="color: #333;">SwiftUIHTML Stress Test</h1>
                    <p style="color: #666;">Synthetic HTML payload exercising tags, CSS, and attachments.</p>
                    <p style="color: #666; font-size: 12px;">
                        Inline styling: <span style="color: #6a2; font-size: 14px;">font-size</span>,
                        <span style="background-color: #ffe08a; border-radius: 4px;">background + radius</span>,
                        <span style="font-family: Georgia;">font-family</span>.
                    </p>
                </header>
                <main>
            """)

        chunks.append("""
            <section style="margin: 12px 0; padding: 12px; border: 1px solid #ddd; border-radius: 6px;">
                <h2 style="color: #1a4; font-size: 18px;">Feature Overview</h2>
                <p style="line-height: 22px;">
                    <strong>Text styles</strong> with <em>nested emphasis</em> and
                    <span style="color: #955;">inline color</span>.
                    <span style="background-color: #ddefff; border-radius: 3px;">Inline background</span>
                    with <u>underline</u> and <b>bold</b>.
                </p>
                <p style="line-height: 22px;">
                    Ruby variants:
                    <ruby ruby-position="before" ruby-scale="0.55" ruby-annotation-font-name="Hiragino Mincho ProN" ruby-annotation-font-size="10">表現<rt>ひょうげん</rt></ruby>,
                    <ruby ruby-position="after" ruby-scale="0.5">漢字<rt>かんじ</rt><rp>(</rp><rt>ignored</rt><rp>)</rp></ruby>,
                    <ruby ruby-position="interCharacter" ruby-scale="0.6">東京<rt>とうきょう</rt></ruby>,
                    <ruby ruby-position="inline" ruby-scale="0.7">可愛い<rt>かわいい</rt></ruby>.
                </p>
            </section>
            """)

        for index in 1...sectionCount {
            let mediaHTML: String
            if includeMedia {
                mediaHTML = """
                    <p>
                        <img src="https://picsum.photos/seed/\(index)/80/60" width="80" height="60" />
                        <video src="https://example.com/video\(index).mp4" />
                    </p>
                    """
            } else {
                mediaHTML = ""
            }

            chunks.append("""
                <section style="margin: 12px 0; padding: 12px; border: 1px solid #ddd; border-radius: 6px;">
                    <h2 style="color: #1a4; font-size: 18px;">Section \(index)</h2>
                    <h3 style="color: #444;">Subtitle \(index)</h3>
                    <p style="line-height: 20px;">
                        Inline styles: <span style="color: #c33;">red</span>,
                        <span style="background-color: #ff0;">yellow</span>,
                        <strong>bold</strong>, <em>italic</em>, <u>underline</u>.
                    </p>
                    <p style="line-height: 20px;">
                        Font family mix:
                        <span style="font-family: Georgia; font-size: 14px;">Georgia 14px</span>,
                        <span style="font-family: Courier; font-size: 12px;">Courier 12px</span>,
                        <span style="font-size: 16px;">Size 16px</span>.
                    </p>
                    <p style="word-break: break-all;">
                        LongWord\(index)WithNoBreaksToExerciseLineWrappingAcrossTheLayoutEngine.
                    </p>
                    <p>
                        Ruby: <ruby ruby-position="after" ruby-scale="0.5">漢字<rt>かんじ</rt></ruby>,
                        <ruby ruby-position="before" ruby-scale="0.6">現代語<rt>げんだいご</rt></ruby>,
                        <ruby ruby-position="inline" ruby-scale="0.7">新年<rt>しんねん</rt></ruby>.
                    </p>
                    <p>
                        Link: <a href="https://example.com/\(index)">example.com/\(index)</a>
                    </p>
                    <ul>
                        <li>Item \(index).1</li>
                        <li>Item \(index).2 with <span style="color: #05a;">color</span></li>
                        <li>Item \(index).3 with <strong>bold</strong> and <em>italic</em></li>
                    </ul>
                    <div style="margin: 8px 0; padding: 8px; border: 1px solid #aac; border-radius: 8px; background-color: #f8fbff;">
                        <p style="margin: 0; line-height: 20px;">
                            Nested block with padding, margin, border, and background.
                            <span style="background-color: #def; border-radius: 4px;">Inline badge</span>
                            + <span style="color: #2a6;">green text</span>.
                        </p>
                    </div>
                    \(mediaHTML)
                </section>
                """)
        }

        chunks.append("""
                </main>
                <footer style="margin-top: 16px; padding: 12px; background-color: #333; color: white;">
                    <p>Footer content for synthetic payload.</p>
                </footer>
            </body>
            """)

        return chunks.joined(separator: "\n")
    }
}

#Preview {
    NavigationView {
        SyntheticStressSample()
    }
}
