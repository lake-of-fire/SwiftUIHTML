# SwiftUIHTML

![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)
[![SPM](https://img.shields.io/badge/SPM-compatible-4BC51D.svg)](https://github.com/apple/swift-package-manager)
[![License](https://img.shields.io/badge/license-MIT-lightgrey.svg)](LICENSE)

**SwiftUIHTML**은 SwiftUI에서 HTML 콘텐츠를 네이티브 뷰로 렌더링하는 강력하고 커스터마이즈 가능한 라이브러리입니다.

[View English Documentation](README.md)

## 데모

![SwiftUIHTML Demo](Screen%20Recording.gif)

---

## 🚀 주요 기능

- **HTML 렌더링**: SwiftUI 환경에서 HTML을 네이티브 뷰로 변환
- **커스텀 태그 시스템**: BlockTag, InlineTag, InlineAttachmentTag 프로토콜로 자유로운 확장
- **CSS 스타일 지원**: 인라인 스타일(padding, margin, background, border 등) 완벽 지원
- **유연한 파서 통합**: SwiftSoup 및 커스텀 파서와 연동
- **환경 값 시스템**: 전역 설정 관리 및 스타일 커스터마이징
- **프로파일링 훅**: `SWIFTUIHTML_SIGNPOSTS=1` 설정 시 HTML 파싱 구간 signpost 출력

---

## 📋 지원 태그

### 기본 제공 태그

| 카테고리 | 태그 |
|---------|-----|
| **블록** | `div`, `body`, `p`, `header`, `main`, `section`, `footer`, `h1`, `h2` |
| **인라인** | `span`, `a`, `b`, `strong`, `i`, `em`, `u` |
| **첨부** | `img`, `ruby` |

> 참고: h3, ul, video 등의 태그는 커스텀 태그로 등록하여 사용할 수 있습니다.

> 참고: `ruby`는 `<ruby><rt>` 형태의 주석을 CoreText로 렌더링합니다. `rt` 텍스트가 루비 문자열로 사용되며 `rp`/`rtc`는 무시됩니다.

### CSS 스타일 속성
- **텍스트 스타일**: `color`, `background-color`, `font-family`, `font-size`, `line-height`, `word-break`
- **블록 레이아웃**: `padding`, `margin`, `border`, `border-radius` (div, p, section 등 block 요소만)
- **인라인 스타일**: `color`, `background-color`, `border-radius` (strong, em, span 등 inline 요소)

> **참고**: inline 요소(span, strong, em 등)에서는 `padding`, `margin`이 지원되지 않습니다.
> **루비 옵션**: `ruby-position` (`before`, `after`, `interCharacter`, `inline`), `ruby-scale` (예: `0.58`), `ruby-font-name`, `ruby-font-size`, `ruby-annotation-font-name`, `ruby-annotation-font-size`.

---

## 📦 설치 방법

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

## 🛠️ 빠른 시작

### 기본 사용법

```swift
import SwiftUI
import SwiftUIHTML

struct ContentView: View {
    let html = """
        <h1>안녕하세요, SwiftUIHTML!</h1>
        <p>이것은 <strong>굵은 글씨</strong>와 <em>기울임 글씨</em>가 포함된 단락입니다.</p>
        <img src="https://example.com/image.jpg" width="100" height="100" />
        """
    
    var body: some View {
        HTMLView(html: html, parser: HTMLSwiftSoupParser())
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

환경 변수 `SWIFTUIHTML_SIGNPOSTS=1`을 설정하면 HTML 파싱 구간에 signpost가 출력됩니다. Instruments에서 “HTML parse” 구간을 확인하세요.
성능 비교용으로 `SWIFTUIHTML_CACHE_FRAMESETTER=1`을 켜거나 `SWIFTUIHTML_DISABLE_RANGE_SCAN_OPT=1`로 레거시 범위 스캔 경로를 강제로 사용할 수 있습니다.

### Performance Tests

SwiftUIHTML 패키지에는 synthetic HTML 파싱의 median 시간을 출력하는 가벼운 성능 스모크 테스트가 포함되어 있습니다(SwiftSoup 사용 시 추가 측정). SwiftUIHTML 패키지에서 `swift test`를 실행하면 결과가 출력됩니다.

### 루비 예제

```swift
let html = """
    <p>
        <ruby ruby-position="after" ruby-scale="0.5">
            今日<rt>きょう</rt>
        </ruby>
        는 맑습니다.
    </p>
    <p>
        <ruby ruby-font-size="22" ruby-annotation-font-size="12">
            明日<rt>あした</rt>
        </ruby>
        도 맑습니다.
    </p>
    """
```

### 파서 구현

HTMLParserable 프로토콜을 구현하여 원하는 HTML 파서를 사용할 수 있습니다:

```swift
struct MyHTMLParser: HTMLParserable {
    func parse(html: String) -> HTMLNode {
        // 파서 구현
    }
}
```

> 📚 **상세 파서 구현 예제**: [Documentation/ParserIntegration.md](Documentation/ParserIntegration.md)

---

## 📚 문서

상세한 사용법과 예제는 Documentation 폴더를 참고하세요:

- 📖 **[기본 사용법](Documentation/BasicUsage.md)** - HTML 렌더링 기초
- 🎨 **[스타일링 가이드](Documentation/Styling.md)** - CSS 스타일과 설정
- 🔧 **[커스텀 태그](Documentation/CustomTags.md)** - 커스텀 태그 만들기
- 🔌 **[파서 통합](Documentation/ParserIntegration.md)** - SwiftSoup 및 커스텀 파서 연동
- 🚀 **[고급 기능](Documentation/AdvancedFeatures.md)** - 환경값과 고급 커스터마이징

### 빠른 예제

#### 커스텀 태그 등록

```swift
// 간단한 커스텀 태그 등록
let configuration = HTMLConfiguration.default
    .register(tag: "video", renderer: VideoTag.self)
    .register(tag: "h3", renderer: HeadingLevel3.self)
```

#### CSS 스타일 적용

```swift
let html = """
    <div style="padding: 20px; background-color: #f0f0f0; border-radius: 8px;">
        <h2 style="color: #333;">스타일 예제</h2>
    </div>
    """
```

#### 줄바꿈 모드 설정

```swift
var container = HTMLStyleContainer()
container.lineBreakMode = .byWordWrapping  // 또는 .byCharWrapping
```

---

## 🔍 주요 컴포넌트

### HTMLView
HTML 콘텐츠를 렌더링하는 메인 뷰

### HTMLConfiguration  
태그 렌더러 등록 및 관리

### HTMLStyleContainer
전역 텍스트 스타일 설정

### HTMLParserable
외부 HTML 파서 연동 프로토콜

---

## 📱 예제 프로젝트

더 많은 예제는 `Example` 폴더의 프로젝트를 참고하세요.
Testing 섹션에 대용량 HTML을 위한 "Synthetic Stress" 샘플이 있습니다.
SwiftSoup를 연결한 경우 Parser Integration 섹션에 SwiftSoup 파서 샘플이 표시됩니다.

---

## 🤝 기여하기

기여를 환영합니다! 이슈나 PR을 자유롭게 제출해주세요.

---

## 📄 라이선스

Copyright © 2025 PRND. All rights reserved.
