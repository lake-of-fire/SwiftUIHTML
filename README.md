# SwiftUIHTML

![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)
[![SPM](https://img.shields.io/badge/SPM-compatible-4BC51D.svg)](https://github.com/apple/swift-package-manager)
[![License](https://img.shields.io/badge/license-MIT-lightgrey.svg)](LICENSE)

**SwiftUIHTML** is a powerful and customizable library for rendering HTML content as native views in SwiftUI.

[한글 문서 보기 (Korean Documentation)](README_ko.md)

## Demo

![SwiftUIHTML Demo](Screen%20Recording.gif)

---

## 🚀 Key Features

- **HTML Rendering**: Convert HTML to native SwiftUI views
- **Custom Tag System**: Extensible through BlockTag, InlineTag, and InlineAttachmentTag protocols
- **CSS Style Support**: Full inline style support (padding, margin, background, border, etc.)
- **Flexible Parser Integration**: Works with external parsers like Fuzi and SwiftSoup
- **Environment Value System**: Global configuration and style customization
- **Profiling Hooks**: Optional signposts for HTML parsing via `SWIFTUIHTML_SIGNPOSTS=1`

---

## 📋 Supported Tags

### Built-in Tags

| Category | Tags |
|----------|------|
| **Block** | `div`, `body`, `p`, `header`, `main`, `section`, `footer`, `h1`, `h2` |
| **Inline** | `span`, `a`, `b`, `strong`, `i`, `em`, `u` |
| **Attachment** | `img`, `ruby` |

> Note: Tags like h3, ul, video can be registered as custom tags.

> Note: `ruby` renders `<ruby><rt>` annotations via CoreText. `<rt>` text is used for the ruby string; `<rp>`/`<rtc>` are ignored.

### CSS Style Properties
- **Text Styles**: `color`, `background-color`, `font-family`, `font-size`, `line-height`, `word-break`
- **Block Layout**: `padding`, `margin`, `border`, `border-radius` (block elements only: div, p, section, etc.)
- **Inline Styles**: `color`, `background-color`, `border-radius` (inline elements: strong, em, span, etc.)

> **Note**: `padding` and `margin` are not supported for inline elements (span, strong, em, etc.).
> **Ruby options**: `ruby-position` (`before`, `after`, `interCharacter`, `inline`), `ruby-scale` (e.g. `0.58`), `ruby-font-name`, `ruby-font-size`, `ruby-annotation-font-name`, `ruby-annotation-font-size`.

---

## 📦 Installation

### Swift Package Manager (SPM)

```swift
dependencies: [
    .package(url: "https://github.com/PRNDcompany/SwiftUIHTML.git", from: "1.0.0"),
],
targets: [
    .target(name: "YourTarget", dependencies: ["SwiftUIHTML"]),
]
```

---

## 🛠️ Quick Start

### Basic Usage

```swift
import SwiftUI
import SwiftUIHTML

struct ContentView: View {
    let html = """
        <h1>Hello, SwiftUIHTML!</h1>
        <p>This is a <strong>paragraph</strong> with <em>styled</em> text.</p>
        <img src="https://example.com/image.jpg" width="100" height="100" />
        """
    
    var body: some View {
        HTMLView(html: html, parser: HTMLFuziParser())
            .htmlEnvironment(\.configuration, .default)
            .htmlEnvironment(\.styleContainer, createStyleContainer())
    }
    
    func createStyleContainer() -> HTMLStyleContainer {
        var container = HTMLStyleContainer()
#if os(macOS)
        let font = NSFont.systemFont(ofSize: 16)
#else
        let font = UIFont.systemFont(ofSize: 16)
#endif
        container.uiFont = font
        container.lineBreakMode = .byWordWrapping
        return container
    }
}
```

### Profiling

Set `SWIFTUIHTML_SIGNPOSTS=1` in your environment to emit signposts around HTML parsing, then use Instruments to view the “HTML parse” intervals.
For perf comparisons, you can also toggle `SWIFTUIHTML_CACHE_FRAMESETTER=1` and use `SWIFTUIHTML_DISABLE_RANGE_SCAN_OPT=1` to force the legacy range scan path.

### Performance Tests

The SwiftUIHTML package includes lightweight performance smoke tests that log the median parse time for synthetic HTML (and SwiftSoup when available). Run `swift test` in the SwiftUIHTML package to see the output.

### Ruby Example

```swift
let html = """
    <p>
        <ruby ruby-position="after" ruby-scale="0.5">
            今日<rt>きょう</rt>
        </ruby>
        is sunny.
    </p>
    <p>
        <ruby ruby-font-size="22" ruby-annotation-font-size="12">
            明日<rt>あした</rt>
        </ruby>
        is clear too.
    </p>
    """
```

### Parser Implementation

You can use any HTML parser by implementing the HTMLParserable protocol:

```swift
struct MyHTMLParser: HTMLParserable {
    func parse(html: String) -> HTMLNode {
        // Parser implementation
    }
}
```

> 📚 **Detailed parser implementation examples**: [Documentation/ParserIntegration.md](Documentation/ParserIntegration.md)

---

## 📚 Documentation

For detailed usage and examples, please refer to the Documentation folder:

- 📖 **[Basic Usage](Documentation/BasicUsage.md)** - HTML rendering basics
- 🎨 **[Styling Guide](Documentation/Styling.md)** - CSS styles and configuration
- 🔧 **[Custom Tags](Documentation/CustomTags.md)** - Creating custom tags
- 🔌 **[Parser Integration](Documentation/ParserIntegration.md)** - Fuzi, SwiftSoup integration
- 🚀 **[Advanced Features](Documentation/AdvancedFeatures.md)** - Environment values and advanced customization

### Quick Examples

#### Register Custom Tag

```swift
// Simple custom tag registration
let configuration = HTMLConfiguration.default
    .register(tag: "video", renderer: VideoTag.self)
    .register(tag: "h3", renderer: HeadingLevel3.self)
```

#### Apply CSS Styles

```swift
let html = """
    <div style="padding: 20px; background-color: #f0f0f0; border-radius: 8px;">
        <h2 style="color: #333;">Style Example</h2>
    </div>
    """
```

#### Line Break Mode

```swift
var container = HTMLStyleContainer()
container.lineBreakMode = .byWordWrapping  // or .byCharWrapping
```

---

## 🔍 Key Components

### HTMLView
Main view for rendering HTML content

### HTMLConfiguration  
Register and manage tag renderers

### HTMLStyleContainer
Global text style configuration

### HTMLParserable
Protocol for external HTML parser integration

---

## 📱 Example Project

For more examples, please refer to the project in the `Example` folder.
The Testing section includes a "Synthetic Stress" sample for profiling large HTML payloads.
When SwiftSoup is linked, the Parser Integration section includes a SwiftSoup parser sample.

---

## 🤝 Contributing

Contributions are welcome! Feel free to submit issues and pull requests.

---

## 📄 License

SwiftUIHTML is released under the MIT License. See [LICENSE](LICENSE) for details.
