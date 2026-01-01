//  Copyright © 2025 PRND. All rights reserved.
import Foundation

/// Class that provides HTML document compression functionality
public enum HTMLMinifier {
    private static let whitespaceBetweenTagsRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: ">([\\s]+)<",
        options: []
    )

    /// Removes unnecessary whitespace from HTML documents and optimizes them.
    /// - Parameter html: Original HTML string
    /// - Returns: Optimized HTML string
    public static func minify(_ html: String) -> String {
        guard html.count > 3 else { return html }
        // 1. Remove whitespace and line breaks after <br> tags
        var result = html.replacingOccurrences(of: "<br\\s*/?>[\\s\\n\\r]+", with: "<br>", options: .regularExpression)

        // 2. Remove whitespace with line breaks between regular tags
        result = result.replacingOccurrences(of: ">\\s*[\\n\\r]\\s*<", with: "><", options: .regularExpression)

        // 3. Convert only pure whitespace between tags to &nbsp; (when no line breaks)
        if let regex = whitespaceBetweenTagsRegex {
            let fullRange = NSRange(result.startIndex..<result.endIndex, in: result)
            let matches = regex.matches(in: result, range: fullRange)
            for match in matches.reversed() {
                guard match.numberOfRanges > 1,
                      let matchRange = Range(match.range(at: 0), in: result),
                      let spacesRange = Range(match.range(at: 1), in: result) else {
                    continue
                }
                let spacesCount = result[spacesRange].count
                let nbspString = String(repeating: "&nbsp;", count: spacesCount)
                result.replaceSubrange(matchRange, with: ">" + nbspString + "<")
            }
        }

        // 4. Remove all remaining line breaks and tabs (excluding inside tags)
        result = result.replacingOccurrences(of: ">([^<]*?)[\\n\\r\\t]+([^<]*?)<", with: ">$1 $2<", options: .regularExpression)
        result = result.replacingOccurrences(of: "\t", with: " ")

        return result
    }


}
