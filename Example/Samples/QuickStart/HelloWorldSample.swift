//  Copyright © 2025 PRND. All rights reserved.

import SwiftUI
import SwiftUIHTML

struct HelloWorldSample: View {
    let html = """
        <h1>Hello, World!</h1>
        <p>Welcome to the SwiftUIHTML library.</p>
        <p>This is the simplest HTML rendering example.</p>
        """
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Title
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hello SwiftUIHTML")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("The most basic HTML rendering example")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                // HTML rendering
                HTMLView(html: html, parser: HTMLSwiftSoupParser())
                    .htmlEnvironment(\.configuration, .sample)
                    .htmlEnvironment(\.styleContainer, .sample(by: .byWordWrapping))
                    .padding()
                    .background(Color.platformSystemGray6)
                    .cornerRadius(8)
                
                // Code
                VStack(alignment: .leading, spacing: 8) {
                    Text("Swift Code")
                        .font(.headline)
                    
                    Text("""
let html = \"\"\"
    <h1>Hello, World!</h1>
    <p>Welcome to the SwiftUIHTML library.</p>
    <p>This is the simplest HTML rendering example.</p>
\"\"\"

HTMLView(html: html, parser: HTMLSwiftSoupParser())
    .htmlEnvironment(\\.configuration, .sample)
    .htmlEnvironment(\\.styleContainer, .sample(by: .byWordWrapping))
""")
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .background(Color.platformSystemGray6)
                    .cornerRadius(8)
                }
                
                // Description
                VStack(alignment: .leading, spacing: 8) {
                    Text("Key Points")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("• HTMLView: Main component for rendering HTML")
                        Text("• HTMLSwiftSoupParser: Parser using the SwiftSoup library")
                        Text("• .sample: Default configuration for examples")
                        Text("• .byWordWrapping: Word-based line breaking")
                    }
                    .font(.body)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Hello SwiftUIHTML")
        .applyInlineNavigationTitleDisplayMode()
    }
}

#Preview {
    NavigationView {
        HelloWorldSample()
    }
}