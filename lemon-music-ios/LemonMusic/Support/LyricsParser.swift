//
//  LyricsParser.swift
//  LemonMusic
//

import Foundation

struct LyricLine: Identifiable, Equatable {
    let id = UUID()
    let time: Double
    let text: String

    static func == (lhs: LyricLine, rhs: LyricLine) -> Bool {
        lhs.time == rhs.time && lhs.text == rhs.text
    }
}

enum LyricsParser {
    /// 解析 LRC：支持多时间标签 [mm:ss.xx]，忽略元信息行
    static func parse(_ lrc: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        let pattern = #"\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        for rawLine in lrc.components(separatedBy: .newlines) {
            let ns = rawLine as NSString
            let matches = regex.matches(in: rawLine, range: NSRange(location: 0, length: ns.length))
            guard !matches.isEmpty else { continue }
            let text = regex.stringByReplacingMatches(in: rawLine,
                                                      range: NSRange(location: 0, length: ns.length),
                                                      withTemplate: "").trimmingCharacters(in: .whitespaces)
            for match in matches {
                func group(_ i: Int) -> String {
                    let r = match.range(at: i)
                    return r.location != NSNotFound ? ns.substring(with: r) : "0"
                }
                let minutes = Double(group(1)) ?? 0
                let seconds = Double(group(2)) ?? 0
                let fracStr = group(3)
                var frac = 0.0
                if !fracStr.isEmpty {
                    frac = (Double(fracStr) ?? 0) / pow(10, Double(fracStr.count))
                }
                lines.append(LyricLine(time: minutes * 60 + seconds + frac, text: text))
            }
        }
        return lines.sorted { $0.time < $1.time }
    }

    /// 当前行索引
    static func currentIndex(in lines: [LyricLine], at time: Double) -> Int? {
        guard !lines.isEmpty else { return nil }
        var result = 0
        for (i, line) in lines.enumerated() {
            if line.time <= time + 0.15 {
                result = i
            } else {
                break
            }
        }
        return result
    }
}
