//
//  MarkdownTextConverter.swift
//  PasteMemo
//
//  作者：mao.tao
//

import Foundation

/// 将 Markdown 格式的剪贴板文本转换为排版干净的纯文本，同时保留清晰的阅读结构（标题、列表序号、代码块正文、制表符表格等）
/// 纯 String → String 纯函数实现，方便快捷面板与详情视图共享逻辑
enum MarkdownTextConverter {

    // MARK: - 静态预编译正则规则（避免主线程每次重复编译）

    private struct InlineRule {
        let regex: NSRegularExpression
        let template: String
    }

    /// 行内排版替换规则（图片、链接、粗体、斜体、删除线等）
    private static let inlineRules: [InlineRule] = [
        // 移除图片标记
        (#"!\[[^\]\n]*\]\([^)\n]*\)"#, ""),
        // [url](url) 替换为 url；[label](url) 替换为 label
        (#"\[([^\]\n]+)\]\(\1\)"#, "$1"),
        (#"\[([^\]\n]*)\]\([^)\n]*\)"#, "$1"),
        // 引用式链接 [label][ref] 替换为 label；尖括号网址 <url> 替换为 url
        (#"\[([^\]\n]*)\]\[[^\]\n]*\]"#, "$1"),
        (#"<(https?://[^>\n]+)>"#, "$1"),
        // 粗体语法
        (#"\*\*([^*\n]+)\*\*"#, "$1"),
        (#"(?<![\w_\\])__([^_\n]+)__(?![\w_])"#, "$1"),
        // 斜体语法（防止误伤变量名中的下划线和算术星号）
        (#"(?<![\w*\\])\*(?!\s)([^*\n]+)(?<!\s)\*(?![\w*])"#, "$1"),
        (#"(?<![\w_\\])_(?!\s)([^_\n]+)(?<!\s)_(?![\w_])"#, "$1"),
        // 删除线语法
        (#"~~([^~\n]+)~~"#, "$1"),
    ].compactMap { pattern, template in
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        return InlineRule(regex: regex, template: template)
    }

    private static let inlineCodeRegex = try? NSRegularExpression(pattern: #"`[^`\n]+`"#)
    private static let unescapeRegex = try? NSRegularExpression(pattern: #"\\([\\`*_{}\[\]()#+.!~<>-])"#)
    private static let headingRegex = try? NSRegularExpression(pattern: #"^ {0,3}#{1,6}\s+"#)
    private static let blockquoteRegex = try? NSRegularExpression(pattern: #"^\s{0,3}>\s?"#)
    private static let tableSeparatorCellRegex = try? NSRegularExpression(pattern: #"^:?-+:?$"#)
    private static let imageOnlyLineRegex = try? NSRegularExpression(pattern: #"^\s*!\[[^\]\n]*\]\([^)\n]*\)\s*$"#)

    // MARK: - 公共接口

    /// 将 Markdown 文本转换为结构整洁的纯文本
    static func toPlainText(_ markdown: String) -> String {
        let lines = droppingFrontmatter(markdown.components(separatedBy: .newlines))

        var output: [String] = []
        var inFence = false
        for line in lines {
            if isFenceLine(line) {
                inFence.toggle()
                continue
            }
            if inFence {
                output.append(line)
                continue
            }
            if isTableSeparatorLine(line) { continue }
            // 表格行转换为制表符分隔，并清理单元格内部的行内排版标记
            if let row = tableRowAsCells(line) {
                output.append(inlineMarkdownStripped(row))
                continue
            }
            if isImageOnlyLine(line) { continue }
            output.append(inlineMarkdownStripped(line))
        }
        return output.joined(separator: "\n")
    }

    /// 移除文本中所有的空行与纯空白行
    static func removeEmptyLines(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: "\n")
    }

    // MARK: - Frontmatter 处理

    /// 剥离文档顶部的 YAML Frontmatter 元数据块
    private static func droppingFrontmatter(_ lines: [String]) -> [String] {
        guard let first = lines.first, isFrontmatterDelimiter(first) else { return lines }
        guard let closeIndex = lines.dropFirst().firstIndex(where: isFrontmatterDelimiter) else {
            return lines
        }
        let content = lines[(closeIndex + 1)...]
            .drop(while: { $0.trimmingCharacters(in: .whitespaces).isEmpty })
        return Array(content)
    }

    private static func isFrontmatterDelimiter(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return (t.allSatisfy { $0 == "-" } && t.count >= 3)
            || (t.allSatisfy { $0 == "." } && t.count >= 3)
    }

    // MARK: - 行级结构转换

    private static func isFenceLine(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("```") || t.hasPrefix("~~~")
    }

    /// 校验是否为 Markdown 表格分隔行（如 `| ------ | :---: |`）
    private static func isTableSeparatorLine(_ line: String) -> Bool {
        guard line.contains("-"), line.contains("|") else { return false }
        var cells = line.components(separatedBy: "|")
        if let first = cells.first, first.trimmingCharacters(in: .whitespaces).isEmpty { cells.removeFirst() }
        if let last = cells.last, last.trimmingCharacters(in: .whitespaces).isEmpty { cells.removeLast() }
        guard cells.count >= 2 else { return false }
        return cells.allSatisfy { cell in
            let t = cell.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, let regex = tableSeparatorCellRegex else { return false }
            return regex.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil
        }
    }

    /// 将 `| a | b |` 解析为以制表符分隔的单元格 `a\tb`；若非有效表格行则返回 nil
    private static func tableRowAsCells(_ line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("|"), t.hasSuffix("|"), t.count >= 2 else { return nil }
        let cells = t.dropFirst().dropLast()
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard cells.contains(where: { !$0.isEmpty }) else { return nil }
        return cells.joined(separator: "\t")
    }

    /// 是否为独立图片行（如 `![alt](url)`）
    private static func isImageOnlyLine(_ line: String) -> Bool {
        guard let regex = imageOnlyLineRegex else { return false }
        return regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
    }

    /// 剥离行内标题、引用标记及行内 Markdown 语法
    private static func inlineMarkdownStripped(_ line: String) -> String {
        var text = line

        // 移除 ATX 标题标记
        if let regex = headingRegex {
            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, range: range), let r = Range(match.range, in: text) {
                text.removeSubrange(r)
            }
        }

        // 移除引用块前缀
        if let regex = blockquoteRegex {
            while true {
                let range = NSRange(text.startIndex..., in: text)
                guard let match = regex.firstMatch(in: text, range: range),
                      let r = Range(match.range, in: text) else { break }
                let rest = text[r.upperBound...]
                if rest.isEmpty {
                    text = ""
                    break
                }
                text.removeSubrange(r)
            }
        }

        // 快速判断：若不包含任何 Markdown 排版标记字符，直接返回，避免不必要的正则计算
        guard text.contains(where: { "*_~[<!`\\".contains($0) }) else {
            return text
        }

        // 保护行内代码块内容，避免代码内部符号被后续排版规则意外剥离
        var codeSpans: [String] = []
        if let regex = inlineCodeRegex {
            let ns = NSMutableString(string: text)
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            // 从右向左替换占位符，保持前面的范围索引有效
            for i in stride(from: matches.count - 1, through: 0, by: -1) {
                codeSpans.insert(ns.substring(with: matches[i].range), at: 0)
                ns.replaceCharacters(in: matches[i].range, with: "\u{E000}\(i)\u{E001}")
            }
            text = ns as String
        }

        // 执行预编译规则替换（支持最多 4 次迭代以处理嵌套格式）
        for _ in 0..<4 {
            var changed = false
            for rule in inlineRules {
                let range = NSRange(text.startIndex..., in: text)
                let next = rule.regex.stringByReplacingMatches(in: text, range: range, withTemplate: rule.template)
                if next != text {
                    text = next
                    changed = true
                }
            }
            if !changed { break }
        }

        // 还原反斜杠转义字符（如 \* → *）
        if let unescape = unescapeRegex {
            let range = NSRange(text.startIndex..., in: text)
            text = unescape.stringByReplacingMatches(in: text, range: range, withTemplate: "$1")
        }

        // 还原受保护的行内代码内容（同时移除外层的反引号）
        for (i, span) in codeSpans.enumerated() {
            let content = span.dropFirst().dropLast()
            text = text.replacingOccurrences(of: "\u{E000}\(i)\u{E001}", with: String(content))
        }
        return text
    }
}
