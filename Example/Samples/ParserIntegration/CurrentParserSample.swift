//  Copyright © 2025 PRND. All rights reserved.

import SwiftUI
import SwiftUIHTML

struct CurrentParserSample: View {
    let html = """
        <h2>Current Parser: HTMLSwiftSoupParser</h2>
        
        <p>This app uses the <strong>SwiftSoup</strong> library to parse HTML.</p>
        
        <div style="border: 1px solid #ccc; padding: 12px; background-color: #f9f9f9;">
            <h3>Features of SwiftSoup Parser:</h3>
            <p>
                • <strong>HTML Parsing</strong>: Robust HTML parsing in Swift<br>
                • <strong>CSS Selectors</strong>: Query and traverse elements<br>
                • <strong>Document Model</strong>: Easy element access and manipulation
            </p>
        </div>
        
        <p>Complex nested structures are also parsed accurately:</p>
        
        <div>
            <section>
                <p>Nested <em>elements are</em> <strong>correctly</strong> processed.</p>
            </section>
        </div>
        """
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Title
                VStack(alignment: .leading, spacing: 8) {
                    Text("Current Parser")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Currently using HTMLSwiftSoupParser")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                // HTML Rendering
                HTMLView(html: html, parser: HTMLSwiftSoupParser())
                    .htmlEnvironment(\.configuration, .sample)
                    .htmlEnvironment(\.styleContainer, .sample(by: .byWordWrapping))
                    .padding()
                    .background(Color.platformSystemGray6)
                    .cornerRadius(8)
                
                // Parser Information
                VStack(alignment: .leading, spacing: 8) {
                    Text("HTMLSwiftSoupParser")
                        .font(.headline)
                    
                    Text("The default parser used in the Example project. Converts HTML to HTMLNode structure based on the SwiftSoup library.")
                        .font(.body)
                }
                
                // Parser Implementation (Partial)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Parser Implementation (Partial)")
                        .font(.headline)
                    
                    Text("""
struct HTMLSwiftSoupParser: HTMLParserable {
    func parse(html: String) -> HTMLNode {
        do {
            let document = try SwiftSoup.parse(html)
            if let body = document.body() {
                return try elementToHTMLNode(element: body)
            }
            let wrapper = try document.select("*").first() ?? document
            return try elementToHTMLNode(element: wrapper)
        } catch {
            return HTMLNode(tag: "div", children: [.text("Parse error")])
        }
    }
}
""")
                    .font(.system(.caption, design: .monospaced))
                    .padding()
                    .background(Color.platformSystemGray6)
                    .cornerRadius(8)
                }
                
                // Advantages
                VStack(alignment: .leading, spacing: 8) {
                    Text("SwiftSoup Parser Advantages")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("• Fast parsing performance")
                        Text("• CSS selector support")
                        Text("• Accurate HTML structure analysis")
                        Text("• Pure Swift parser")
                        Text("• Flexible HTML manipulation")
                    }
                    .font(.body)
                }
                
                // Comparison with other parsers
                VStack(alignment: .leading, spacing: 8) {
                    Text("Parser Selection Guide")
                        .font(.headline)
                    
                    Text("SwiftUIHTML can use any parser that implements the HTMLParserable protocol. You can choose SwiftSoup or custom parsers.")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Current Parser")
        .applyInlineNavigationTitleDisplayMode()
    }
}

#Preview {
    NavigationView {
        CurrentParserSample()
    }
}
