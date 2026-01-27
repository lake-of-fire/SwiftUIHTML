//  Copyright © 2025 PRND. All rights reserved.
import Foundation

/// CSS 폰트 스타일 파싱 및 처리를 담당하는 유틸리티 클래스

public enum CSSFontUtility {


    /// CSS font-family 문자열로부터 fallback이 적용된 UIFont 생성
    /// - Parameters:
    ///   - fontFamilyString: CSS font-family 문자열 (예: "Arial, Helvetica, sans-serif")
    ///   - size: 적용할 폰트 크기
    /// - Returns: 생성된 폰트
    static func createFont(fromFontFamily fontFamilyString: String?, size: CGFloat) -> PlatformFont {
        guard let fontFamilyString = fontFamilyString, !fontFamilyString.isEmpty else {
            return PlatformFont.systemFont(ofSize: size)
        }

        let fontNames = parseFontFamilyString(fontFamilyString)
        return createFontWithFallbacks(fontNames: fontNames, size: size)
    }

    /// CSS font-size 문자열 파싱하여 CGFloat 값으로 변환
    /// - Parameters:
    ///   - fontSizeString: CSS font-size 문자열 (예: "12px", "1.5em", "large")
    ///   - baseSize: 상대 크기 계산을 위한 기준 크기
    /// - Returns: 파싱된 폰트 크기
    static func parseSize(fromFontSize fontSizeString: String?, baseSize: CGFloat = PlatformFont.systemFontSize) -> CGFloat {
        guard let fontSizeString = fontSizeString, !fontSizeString.isEmpty else {
            return baseSize
        }

        let trimmed = ASCIIWhitespace.trim(fontSizeString)
        if trimmed.isEmpty {
            return baseSize
        }
        let trimmedString = String(trimmed)

        // 다양한 단위 처리
        if trimmedString.hasSuffix("px") {
            if let value = Double(trimmedString.dropLast(2)) {
                return CGFloat(value)
            }
        } else if trimmedString.hasSuffix("pt") {
            if let value = Double(trimmedString.dropLast(2)) {
                return CGFloat(value)
            }
        } else if trimmedString.hasSuffix("rem") {
            if let value = Double(trimmedString.dropLast(3)) {
                return baseSize * CGFloat(value)
            }
        } else if trimmedString.hasSuffix("em") {
            if let value = Double(trimmedString.dropLast(2)) {
                return baseSize * CGFloat(value)
            }
        } else if trimmedString.hasSuffix("%") {
            if let value = Double(trimmedString.dropLast(1)) {
                return baseSize * CGFloat(value / 100)
            }
        } else if let value = Double(trimmedString) {
            return CGFloat(value)
        }

        switch trimmedString.lowercased() {
        case "xx-small": return baseSize * 0.6
        case "x-small": return baseSize * 0.75
        case "small": return baseSize * 0.889
        case "medium": return baseSize
        case "large": return baseSize * 1.2
        case "x-large": return baseSize * 1.5
        case "xx-large": return baseSize * 2.0
        case "xxx-large": return baseSize * 3.0
        case "smaller": return baseSize * 0.8
        case "larger": return baseSize * 1.2
        default: return baseSize
        }
    }

    /// CSS 스타일에서 폰트 관련 속성을 추출하여 UIFont 생성
    /// - Parameters:
    ///   - cssStyle: CSS 스타일 딕셔너리
    ///   - currentFont: 현재 설정된 폰트 (기준 크기 및 업데이트용)
    /// - Returns: 생성된 폰트
    static func createFont(fromCSSStyle cssStyle: CSSStyle, currentFont: PlatformFont? = nil) -> PlatformFont? {
        let currentSize = currentFont?.pointSize ?? PlatformFont.systemFontSize

        // font-size와 font-family 속성 추출
        let fontSizeValue = cssStyle["font-size"]?.string
        let fontFamilyValue = cssStyle["font-family"]?.string

        // font 속성이 있다면 해당 속성 파싱 (예: "italic bold 16px/2 Arial, sans-serif")
        if let fontShorthand = cssStyle["font"]?.string {
            let (extractedSize, extractedFamily) = parseFontShorthand(fontShorthand)

            // 개별 속성보다 shorthand 속성이 우선순위가 낮음
            if fontSizeValue == nil, let size = extractedSize {
                let parsedSize = parseSize(fromFontSize: size, baseSize: currentSize)

                if fontFamilyValue == nil, let family = extractedFamily {
                    return createFont(fromFontFamily: family, size: parsedSize)
                } else if let family = fontFamilyValue {
                    return createFont(fromFontFamily: family, size: parsedSize)
                } else {
                    return currentFont?.withSize(parsedSize) ?? PlatformFont.systemFont(ofSize: parsedSize)
                }
            }
        }

        // font-size 처리
        let size = parseSize(fromFontSize: fontSizeValue, baseSize: currentSize)

        // font-family가 있으면 해당 폰트로, 없으면 현재 폰트의 사이즈만 변경
        if let fontFamily = fontFamilyValue {
            return createFont(fromFontFamily: fontFamily, size: size)
        } else if size != currentSize {
            return currentFont?.withSize(size) ?? PlatformFont.systemFont(ofSize: size)
        }

        return currentFont
    }

    // MARK: - Private Helper Methods

    private static func parseFontFamilyString(_ fontFamilyString: String) -> [String] {
        let parts = splitByComma(fontFamilyString)
        var results: [String] = []
        results.reserveCapacity(parts.count)

        for part in parts {
            let trimmed = trimASCIIAndQuotes(part)
            guard !trimmed.isEmpty else { continue }
            results.append(String(trimmed))
        }

        return results
    }

    private static func createFontWithFallbacks(fontNames: [String], size: CGFloat) -> PlatformFont {
        // 특정 폰트 이름과 제네릭 패밀리 분리
        var specificFontNames: [String] = []
        var genericFamily: String? = nil

        for name in fontNames {
            if isGenericFontFamily(name) {
                genericFamily = name
            } else {
                specificFontNames.append(name)
            }
        }

        // 첫 번째 유효한 폰트 찾기
        var primaryFont: PlatformFont! = nil
        for name in specificFontNames {
            if let font = PlatformFont(name: name, size: size) {
                primaryFont = font
                break
            }
        }

        // 유효한 폰트가 없으면 제네릭이나 시스템 폰트 사용
        if primaryFont == nil {
            if let genericFamily = genericFamily {
                return createSystemFontForGenericFamily(genericFamily, size: size)
            }
            return PlatformFont.systemFont(ofSize: size)
        }

        // 기본 폰트의 descriptor 가져오기
        let primaryDescriptor = primaryFont!.fontDescriptor

        // Cascade 목록 생성
        var cascadeList: [PlatformFontDescriptor] = []

        // Fallback 폰트 추가 (첫 번째 이후의 특정 폰트들)
        if specificFontNames.count > 1 {
            for name in specificFontNames.dropFirst() {
                if let font = PlatformFont(name: name, size: size) {
                    cascadeList.append(font.fontDescriptor)
                }
            }
        }

        // 제네릭 폰트 추가
        if let genericFamily = genericFamily {
            let genericFont = createSystemFontForGenericFamily(genericFamily, size: size)
            cascadeList.append(genericFont.fontDescriptor)
        }

        // 최종 fallback으로 시스템 폰트 추가
        cascadeList.append(PlatformFont.systemFont(ofSize: size).fontDescriptor)

        // cascade 목록이 비어있지 않으면 descriptor 업데이트
        if !cascadeList.isEmpty {
            let descriptorWithCascade = primaryDescriptor.addingAttributes([
                PlatformFontDescriptor.AttributeName.cascadeList: cascadeList
            ])
#if os(macOS)
            return PlatformFont(descriptor: descriptorWithCascade, size: 0) ?? primaryFont // 0은 원래 크기 유지
#else
            return PlatformFont(descriptor: descriptorWithCascade, size: 0) // 0은 원래 크기 유지
#endif
        }

        return primaryFont
    }

    private static func isGenericFontFamily(_ name: String) -> Bool {
        let genericFamilies = ["serif", "sans-serif", "monospace", "cursive", "fantasy", "system-ui"]
        return genericFamilies.contains(name.lowercased())
    }

    private static func createSystemFontForGenericFamily(_ family: String, size: CGFloat) -> PlatformFont {
        switch family.lowercased() {
        case "serif":
            return PlatformFont(name: "TimesNewRomanPSMT", size: size) ?? PlatformFont.systemFont(ofSize: size)
        case "sans-serif":
            return PlatformFont.systemFont(ofSize: size)
        case "monospace":
            if #available(iOS 13.0, macOS 10.15, *) {
                return PlatformFont.monospacedSystemFont(ofSize: size, weight: .regular)
            }
            return PlatformFont(name: "Menlo-Regular", size: size) ?? PlatformFont.systemFont(ofSize: size)
        case "cursive":
            return PlatformFont(name: "SnellRoundhand", size: size) ?? PlatformFont.systemFont(ofSize: size)
        case "fantasy":
            return PlatformFont(name: "Papyrus", size: size) ?? PlatformFont.systemFont(ofSize: size)
        case "system-ui":
            return PlatformFont.systemFont(ofSize: size)
        default:
            return PlatformFont.systemFont(ofSize: size)
        }
    }

    private static func parseFontShorthand(_ fontString: String) -> (size: String?, family: String?) {
        // font: [font-style] [font-variant] [font-weight] [font-size/line-height] [font-family]
        // 예: "italic bold 16px/2 Arial, sans-serif"

        let components = splitByASCIIWhitespace(fontString)

        // 마지막 요소가 폰트 패밀리 (쉼표로 구분된 목록일 수 있음)
        var familyStartIndex = -1
        for (index, component) in components.enumerated().reversed() {
            if containsCommaASCII(component) || isGenericFontFamily(String(component)) {
                familyStartIndex = index
                break
            }
        }

        // 폰트 패밀리 조합
        var fontFamily: String? = nil
        if familyStartIndex >= 0 {
            fontFamily = components[familyStartIndex...].map(String.init).joined(separator: " ")
        }

        // 폰트 사이즈 찾기 (px, pt, em, rem, % 등으로 끝나는 요소)
        var fontSize: String? = nil
        for component in components {
            let componentString = String(component)
            if componentString.hasSuffix("px") || componentString.hasSuffix("pt") ||
               componentString.hasSuffix("em") || componentString.hasSuffix("rem") ||
               componentString.hasSuffix("%") ||
               ["xx-small", "x-small", "small", "medium", "large", "x-large", "xx-large", "xxx-large", "smaller", "larger"].contains(componentString.lowercased()) {
                let sizeSlice = prefixBeforeSlash(component)
                fontSize = String(sizeSlice) // line-height 제거
                break
            }
        }

        return (fontSize, fontFamily)
    }
}

private extension CSSFontUtility {
    static func splitByComma(_ value: String) -> [Substring] {
        let utf8 = value.utf8
        var results: [Substring] = []
        results.reserveCapacity(4)

        var start = utf8.startIndex
        var index = start
        while index < utf8.endIndex {
            if utf8[index] == 0x2C { // ","
                let startIndex = String.Index(start, within: value) ?? value.startIndex
                let endIndex = String.Index(index, within: value) ?? value.endIndex
                results.append(value[startIndex..<endIndex])
                start = utf8.index(after: index)
            }
            index = utf8.index(after: index)
        }

        if start <= utf8.endIndex {
            let startIndex = String.Index(start, within: value) ?? value.startIndex
            let endIndex = value.endIndex
            results.append(value[startIndex..<endIndex])
        }

        return results
    }

    static func splitByASCIIWhitespace(_ value: String) -> [Substring] {
        let utf8 = value.utf8
        var results: [Substring] = []
        results.reserveCapacity(8)

        var start = utf8.startIndex
        var index = start
        var inToken = false

        while index < utf8.endIndex {
            let byte = utf8[index]
            if ASCIIWhitespace.isWhitespace(byte) {
                if inToken {
                    let startIndex = String.Index(start, within: value) ?? value.startIndex
                    let endIndex = String.Index(index, within: value) ?? value.endIndex
                    results.append(value[startIndex..<endIndex])
                    inToken = false
                }
                index = utf8.index(after: index)
                start = index
                continue
            }
            if !inToken {
                start = index
                inToken = true
            }
            index = utf8.index(after: index)
        }

        if inToken {
            let startIndex = String.Index(start, within: value) ?? value.startIndex
            results.append(value[startIndex..<value.endIndex])
        }

        return results
    }

    static func trimASCIIAndQuotes(_ value: Substring) -> Substring {
        let trimmed = ASCIIWhitespace.trim(value)
        let utf8 = trimmed.utf8
        guard !utf8.isEmpty else { return trimmed }

        var start = utf8.startIndex
        var end = utf8.endIndex

        let first = utf8[start]
        if first == 0x22 || first == 0x27 { // " or '
            start = utf8.index(after: start)
        }

        if end > start {
            let before = utf8.index(before: end)
            let last = utf8[before]
            if last == 0x22 || last == 0x27 {
                end = before
            }
        }

        let startIndex = String.Index(start, within: trimmed) ?? trimmed.startIndex
        let endIndex = String.Index(end, within: trimmed) ?? trimmed.endIndex
        return trimmed[startIndex..<endIndex]
    }

    static func containsCommaASCII(_ value: Substring) -> Bool {
        for byte in value.utf8 {
            if byte == 0x2C {
                return true
            }
        }
        return false
    }

    static func prefixBeforeSlash(_ value: Substring) -> Substring {
        let utf8 = value.utf8
        if let slashIndex = utf8.firstIndex(of: 0x2F) { // "/"
            let endIndex = String.Index(slashIndex, within: value) ?? value.endIndex
            return value[value.startIndex..<endIndex]
        }
        return value
    }
}
