//  Copyright © 2025 PRND. All rights reserved.
import SwiftUI


extension Color {
    /// Initializes a `Color` from a CSS color string.
    /// - Parameter cssString: The CSS color string (e.g., "rgb(255,0,0)", "#RRGGBB", "red").
    init?(cssString: String) {
        let trimmedCSS = ASCIIWhitespace.trim(cssString)
        let trimmedString = String(trimmedCSS)

        // RGB/RGBA 형식 처리
        if trimmedString.hasPrefix("rgb") {
            if let color = Color.fromRGBString(trimmedString) {
                self = color
                return
            }
        }

        // 16진수 형식 처리
        else if trimmedString.hasPrefix("#") {
            if let color = Color.fromHexString(trimmedString) {
                self = color
                return
            }
        }

        // 명명된 색상 처리
        else if let color = Color.fromNamedColor(trimmedString) {
            self = color
            return
        }

        return nil
    }

    // MARK: - RGB/RGBA 색상 파싱

    /// RGB 또는 RGBA 문자열에서 Color 생성
    private static func fromRGBString(_ rgbString: String) -> Color? {
        if let color = Color.fromRGBStringFast(rgbString) {
            return color
        }
        let rgbPattern = "rgba?\\((\\d+),\\s*(\\d+),\\s*(\\d+)(?:,\\s*([0-9.]+))?\\)"
        guard let regex = try? NSRegularExpression(pattern: rgbPattern, options: []),
              let match = regex.firstMatch(in: rgbString, options: [], range: NSRange(rgbString.startIndex..<rgbString.endIndex, in: rgbString)) else {
            return nil
        }

        // 컴포넌트 추출
        var components: [Double] = []
        for i in 1..<match.numberOfRanges {
            if let range = Range(match.range(at: i), in: rgbString),
               !rgbString[range].isEmpty {
                if let value = Double(rgbString[range]) {
                    components.append(value)
                } else if i == 4 { // Alpha 값
                    components.append(1.0)
                } else {
                    return nil
                }
            } else if i == 4 { // Alpha 범위가 없는 경우
                components.append(1.0)
            } else {
                return nil
            }
        }

        guard components.count >= 3 else { return nil }

        let r = min(max(components[0] / 255.0, 0), 1)
        let g = min(max(components[1] / 255.0, 0), 1)
        let b = min(max(components[2] / 255.0, 0), 1)
        let a = min(max(components.count >= 4 ? components[3] : 1.0, 0), 1)

        return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    private static func fromRGBStringFast(_ rgbString: String) -> Color? {
        let trimmed = ASCIIWhitespace.trim(rgbString)
        let utf8 = trimmed.utf8
        guard utf8.count >= 8 else { return nil }

        var index = utf8.startIndex
        func advance() { index = utf8.index(after: index) }

        // prefix: rgb or rgba
        guard utf8[index] == 0x72, utf8.index(after: index) < utf8.endIndex else { return nil } // r
        advance()
        guard utf8[index] == 0x67, utf8.index(after: index) < utf8.endIndex else { return nil } // g
        advance()
        guard utf8[index] == 0x62 else { return nil } // b
        advance()

        var hasAlpha = false
        if index < utf8.endIndex, utf8[index] == 0x61 { // a
            hasAlpha = true
            advance()
        }

        // skip whitespace
        while index < utf8.endIndex, ASCIIWhitespace.isWhitespace(utf8[index]) {
            advance()
        }

        guard index < utf8.endIndex, utf8[index] == 0x28 else { return nil } // (
        advance()

        var components: [Double] = []
        components.reserveCapacity(hasAlpha ? 4 : 3)

        func parseNumber() -> Double? {
            while index < utf8.endIndex, ASCIIWhitespace.isWhitespace(utf8[index]) {
                advance()
            }
            guard index < utf8.endIndex else { return nil }

            var integer: Double = 0
            var hasDigits = false
            while index < utf8.endIndex {
                let byte = utf8[index]
                if byte >= 0x30 && byte <= 0x39 {
                    integer = integer * 10 + Double(byte - 0x30)
                    hasDigits = true
                    advance()
                } else {
                    break
                }
            }

            var fraction: Double = 0
            var divisor: Double = 1
            if index < utf8.endIndex, utf8[index] == 0x2E { // "."
                advance()
                while index < utf8.endIndex {
                    let byte = utf8[index]
                    if byte >= 0x30 && byte <= 0x39 {
                        fraction = fraction * 10 + Double(byte - 0x30)
                        divisor *= 10
                        hasDigits = true
                        advance()
                    } else {
                        break
                    }
                }
            }

            guard hasDigits else { return nil }
            return integer + fraction / divisor
        }

        for idx in 0..<(hasAlpha ? 4 : 3) {
            guard let value = parseNumber() else { return nil }
            components.append(value)
            while index < utf8.endIndex, ASCIIWhitespace.isWhitespace(utf8[index]) {
                advance()
            }
            if idx < (hasAlpha ? 3 : 2) {
                guard index < utf8.endIndex, utf8[index] == 0x2C else { return nil } // ","
                advance()
            }
        }

        while index < utf8.endIndex, ASCIIWhitespace.isWhitespace(utf8[index]) {
            advance()
        }
        guard index < utf8.endIndex, utf8[index] == 0x29 else { return nil } // ")"

        guard components.count >= 3 else { return nil }
        let r = min(max(components[0] / 255.0, 0), 1)
        let g = min(max(components[1] / 255.0, 0), 1)
        let b = min(max(components[2] / 255.0, 0), 1)
        let a = min(max(components.count >= 4 ? components[3] : 1.0, 0), 1)
        return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    // MARK: - 16진수 색상 파싱

    /// 16진수 문자열에서 Color 생성
    private static func fromHexString(_ hexString: String) -> Color? {
        let trimmed = ASCIIWhitespace.trim(hexString)
        guard !trimmed.isEmpty else { return nil }

        var hexBytes = trimmed.utf8
        if let first = hexBytes.first, first == 0x23 { // "#"
            hexBytes = hexBytes.dropFirst()
        }

        let count = hexBytes.count
        guard count == 3 || count == 4 || count == 6 || count == 8 else {
            return nil
        }

        func hexValue(_ byte: UInt8) -> UInt8? {
            switch byte {
            case 0x30...0x39:
                return byte &- 0x30
            case 0x41...0x46:
                return byte &- 0x37
            case 0x61...0x66:
                return byte &- 0x57
            default:
                return nil
            }
        }

        var parsed: [UInt8] = []
        parsed.reserveCapacity(count == 3 ? 3 : count == 4 ? 4 : count / 2)

        if count == 3 || count == 4 {
            for byte in hexBytes {
                guard let value = hexValue(byte) else { return nil }
                let full = (value << 4) | value
                parsed.append(full)
            }
        } else {
            var index = hexBytes.startIndex
            while index < hexBytes.endIndex {
                let highByte = hexBytes[index]
                let nextIndex = hexBytes.index(after: index)
                if nextIndex >= hexBytes.endIndex {
                    return nil
                }
                let lowByte = hexBytes[nextIndex]
                guard let high = hexValue(highByte),
                      let low = hexValue(lowByte) else {
                    return nil
                }
                parsed.append((high << 4) | low)
                index = hexBytes.index(after: nextIndex)
            }
        }

        let red, green, blue, alpha: Double
        switch parsed.count {
        case 3:
            red = Double(parsed[0]) / 255.0
            green = Double(parsed[1]) / 255.0
            blue = Double(parsed[2]) / 255.0
            alpha = 1.0
        case 4:
            red = Double(parsed[0]) / 255.0
            green = Double(parsed[1]) / 255.0
            blue = Double(parsed[2]) / 255.0
            alpha = Double(parsed[3]) / 255.0
        default:
            return nil
        }

        return Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    // MARK: - 명명된 색상 파싱

    /// 색상 이름에서 Color 생성
    private static func fromNamedColor(_ colorName: String) -> Color? {
        switch colorName.lowercased() {
        // 기본 색상
        case "black": return .black
        case "white": return .white
        case "red": return .red
        case "green": return .green
        case "blue": return .blue
        case "yellow": return .yellow
        case "orange": return .orange
        case "purple": return .purple
        case "pink": return .pink
        case "gray", "grey": return .gray
        case "brown": return .brown
        case "cyan", "aqua": return .cyan
        case "indigo": return .indigo
        case "mint": return .mint
        case "teal": return .teal

        // 특수 색상
        case "clear", "transparent": return .clear

        // 추가 Web 색상 - 필요에 따라 확장
        case "aliceblue": return Color(red: 0.94, green: 0.97, blue: 1.0)
        case "antiquewhite": return Color(red: 0.98, green: 0.92, blue: 0.84)
        case "aquamarine": return Color(red: 0.5, green: 1.0, blue: 0.83)
        case "azure": return Color(red: 0.94, green: 1.0, blue: 1.0)
        case "beige": return Color(red: 0.96, green: 0.96, blue: 0.86)
        case "bisque": return Color(red: 1.0, green: 0.89, blue: 0.77)
        case "blanchedalmond": return Color(red: 1.0, green: 0.92, blue: 0.8)
        case "blueviolet": return Color(red: 0.54, green: 0.17, blue: 0.89)
        case "burlywood": return Color(red: 0.87, green: 0.72, blue: 0.53)
        case "cadetblue": return Color(red: 0.37, green: 0.62, blue: 0.63)
        case "chocolate": return Color(red: 0.82, green: 0.41, blue: 0.12)
        case "coral": return Color(red: 1.0, green: 0.5, blue: 0.31)
        case "cornflowerblue": return Color(red: 0.39, green: 0.58, blue: 0.93)
        case "cornsilk": return Color(red: 1.0, green: 0.97, blue: 0.86)
        case "crimson": return Color(red: 0.86, green: 0.08, blue: 0.24)
        case "darkblue": return Color(red: 0.0, green: 0.0, blue: 0.55)
        case "darkgray", "darkgrey": return Color(red: 0.66, green: 0.66, blue: 0.66)
        case "darkgreen": return Color(red: 0.0, green: 0.39, blue: 0.0)
        case "darkkhaki": return Color(red: 0.74, green: 0.72, blue: 0.42)
        case "darkred": return Color(red: 0.55, green: 0.0, blue: 0.0)

        // 필요한 경우 더 추가 가능

        default: return nil
        }
    }
}
