import Foundation

/// 检测文本是否为代码并识别其语言类型
/// 采用分阶段识别策略：
/// 1. 过滤非代码结构化输出（如运行日志等）
/// 2. 可精确解析语言（JSON/XML/HTML/Vue）——通过解析器直接验证
/// 2.5 Markdown——基于排版结构特征识别（代码块、表格、标题、列表等）
/// 3. highlight.js 自动语言识别（通过 JavaScriptCore）
@MainActor
enum CodeDetector {

    static func isCode(_ text: String) -> Bool {
        detectLanguage(text) != nil
    }

    static func detectLanguage(_ text: String) -> CodeLanguage? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // hljs.highlightAuto on JavaScriptCore blocks the main actor for seconds on
        // >64KB input. Any realistic source file fits comfortably; log dumps and
        // terminal buffers don't need syntax highlighting anyway.
        guard trimmed.utf8.count <= 64 * 1024 else { return nil }

        // Phase 1: reject structured non-code formats
        if isLogOutput(trimmed) { return nil }

        // Phase 2: parseable formats — parsing is 100% accurate, beats regex scoring
        if isVueSFC(trimmed) { return .vue }
        if isValidJSON(trimmed) { return .json }
        if isValidXML(trimmed) { return .xml }
        if isValidHTML(trimmed) { return .html }

        // 第 2.5 阶段：Markdown 结构化识别。highlight.js 对通用 Markdown
        // 文本打分偏低，且常将包含多级标题的文档误判为 Shell 或 Kotlin
        if isMarkdown(trimmed) { return .markdown }

        // Phase 3: highlight.js auto-detection
        guard let result = HighlightEngine.shared.detectLanguage(trimmed) else {
            return nil
        }
        let detected = CodeLanguage.fromHighlightJS(result.language)

        // Phase 4: disambiguation for languages highlight.js confuses
        if let corrected = disambiguate(trimmed, detected: detected) {
            return corrected
        }
        return detected
    }

    // MARK: - Disambiguation

    /// Corrects common highlight.js misdetections where languages have overlapping syntax.
    private static func disambiguate(_ text: String, detected: CodeLanguage?) -> CodeLanguage? {
        guard let detected else { return nil }

        // C# vs TypeScript/JavaScript: highlight.js often confuses these
        if detected == .csharp {
            let hasJSImport = hasMatch(text, #"\bimport\s+.*\s+from\s+['\"]"#)
            let hasExport = hasMatch(text, #"\bexport\s+(const|default|function|class|type|interface|enum)\b"#)
            let hasArrowFn = hasMatch(text, #"=>\s*[\{\(\[]"#)
            let hasRequire = hasMatch(text, #"\brequire\s*\("#)
            let hasConsole = hasMatch(text, #"\bconsole\.\w+\("#)

            if hasJSImport || hasExport || hasArrowFn || hasRequire || hasConsole {
                // Distinguish TS from JS: type annotations, interface, generics
                let hasTypeAnnotation = hasMatch(text, #":\s*(string|number|boolean|any|void|never|unknown)\b"#)
                let hasInterface = hasMatch(text, #"\b(interface|type)\s+\w+\s*[={<]"#)
                let hasGeneric = hasMatch(text, #"\b(Record|Partial|Pick|Omit|Required|Readonly)<"#)
                return (hasTypeAnnotation || hasInterface || hasGeneric) ? .typescript : .javascript
            }
        }

        // C# vs Java: both use namespaces and classes
        if detected == .csharp {
            let hasJavaPackage = hasMatch(text, #"\bpackage\s+[a-z]+(\.[a-z]+)+"#)
            let hasSystemOut = hasMatch(text, #"\bSystem\.out\.\w+"#)
            let hasOverride = hasMatch(text, #"@Override\b"#)
            if hasJavaPackage || hasSystemOut || hasOverride { return .java }
        }

        return nil
    }

    // MARK: - Format-Based Detection (parsing only)

    private static func isVueSFC(_ text: String) -> Bool {
        let hasTemplate = hasMatch(text, #"<template[\s>]"#)
        let hasScript = hasMatch(text, #"<script\b"#)
        guard hasTemplate || hasScript else { return false }
        return hasMatch(text, #"<script\s+setup"#)
            || hasMatch(text, #"<style\s+(scoped|module)"#)
            || hasMatch(text, #"\bv-(for|if|else|else-if|show|model|bind|on|slot|html|text)\b"#)
            || hasMatch(text, #"\b(defineProps|defineEmits|defineExpose|withDefaults)\b"#)
            || hasMatch(text, #"@(click|input|change|submit|keydown|keyup)\b"#)
            || hasMatch(text, #":(key|class|style|is|ref)\b"#)
    }

    private static func isValidJSON(_ text: String) -> Bool {
        guard let first = text.first, first == "{" || first == "[" else { return false }
        guard let data = text.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    private static func isValidXML(_ text: String) -> Bool {
        guard text.hasPrefix("<?xml") || text.hasPrefix("<![CDATA[") else { return false }
        guard let data = text.data(using: .utf8) else { return false }
        return XMLParser(data: data).parse()
    }

    private static func isValidHTML(_ text: String) -> Bool {
        let lower = text.lowercased()
        guard lower.hasPrefix("<!doctype html") || lower.hasPrefix("<html") else { return false }
        return hasMatch(text, #"</?(head|body|div|span|title)\b"#, caseInsensitive: true)
    }

    // MARK: - Non-Code Format Detection

    private static func isLogOutput(_ text: String) -> Bool {
        let lines = text.components(separatedBy: .newlines)
        let nonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard nonEmpty.count >= 2 else { return false }

        let logPatterns: [String] = [
            #"^\[?\w+\]?\s*\[?\d{4}[-/]\d{2}[-/]\d{2}"#,
            #"^\[\w+\]\s+"#,
            #"^\d{4}[-/]\d{2}[-/]\d{2}[\sT]\d{2}:\d{2}:\d{2}"#,
            #"^\w+\s+\d{2}\s+\d{2}:\d{2}:\d{2}\s+"#,
        ]

        let logLineCount = nonEmpty.filter { line in
            logPatterns.contains { hasMatch(line, $0) }
        }.count

        return Double(logLineCount) / Double(nonEmpty.count) > 0.5
    }

    // MARK: - Markdown 结构化识别

    // 预编译正则表达式（避免每次剪贴板变动在主线程重复编译）
    private static let codeMarkerRegex = try? NSRegularExpression(
        pattern: #"\$\{?[A-Za-z_]|\b(fi|done|esac|elif|function|func|struct|enum|import|require|include)\b|=>|==|!=|&&|\|\||;\s*$|\bdef\s+\w+\s*\(|\bfunc\s+\w+\s*\(|\bclass\s+\w+\s*[({:]|\bprint\("#,
        options: [.anchorsMatchLines]
    )
    private static let markdownLinkRegex = try? NSRegularExpression(
        pattern: #"\[[^\]\n]*\]\((https?://|mailto:|/|#|\./)[^)\n]*\)"#
    )
    private static let boldRegex = try? NSRegularExpression(
        pattern: #"\*\*[^*\n]+\*\*"#
    )
    private static let blockquoteRegex = try? NSRegularExpression(
        pattern: #"^\s*>\s+\S"#, options: [.anchorsMatchLines]
    )
    private static let bulletListRegex = try? NSRegularExpression(
        pattern: #"^\s*[-*+]\s+\S"#, options: [.anchorsMatchLines]
    )
    private static let orderedListRegex = try? NSRegularExpression(
        pattern: #"^\s*\d{1,9}[.)]\s+\S"#, options: [.anchorsMatchLines]
    )
    private static let inlineCodeRegex = try? NSRegularExpression(
        pattern: #"`[^`\n]+`"#
    )
    private static let tableSeparatorCellRegex = try? NSRegularExpression(
        pattern: #"^:?-+:?$"#
    )
    private static let headingLineRegex = try? NSRegularExpression(
        pattern: #"^ {0,3}#{1,6}\s+\S"#
    )

    /// 基于结构特征判定文本是否为 Markdown
    /// 涵盖：代码块栅栏、管道表格、超链接、标题、粗体、列表、引用及行内代码
    static func isMarkdown(_ text: String) -> Bool {
        // Shebang 行代表 Shell 脚本，不属于 Markdown
        if text.hasPrefix("#!") { return false }
        let lines = text.components(separatedBy: .newlines)

        // 识别编程语言特征标记，防止脚本注释与操作符被误判为 Markdown 标题或强调符
        let codeMarkers = matchCount(text, regex: codeMarkerRegex)

        var score = 0

        // 明确的代码块栅栏（至少2行匹配或单行带多行内容）与表格分隔线具备强 Markdown 决定性
        let fenceCount = lines.filter(isCodeFenceLine).count
        if fenceCount >= 2 || (fenceCount == 1 && lines.count > 1) { score += 10 }
        if lines.contains(where: isTableSeparatorLine) { score += 10 }

        // 若存在较多编程语言标记（>= 2），则严格抑制外链与排版特征加分，防止含文档链接的代码被误判
        if codeMarkers < 2 {
            if hasMatch(text, regex: markdownLinkRegex) { score += 4 }

            var headingPoints = 0
            var headingLevels: Set<Int> = []
            for (i, line) in lines.enumerated() where headingPoints < 6 {
                guard let level = headingLevel(line) else { continue }
                let next = i + 1 < lines.count ? lines[i + 1] : ""
                let nextTrimmed = next.trimmingCharacters(in: .whitespaces)
                if nextTrimmed.isEmpty || i + 1 == lines.count {
                    headingPoints += 2
                    headingLevels.insert(level)
                } else if !nextTrimmed.hasPrefix("#") {
                    headingPoints += 1
                    headingLevels.insert(level)
                }
            }
            // 单一层级标题不足以判定 Markdown：Dockerfile/YAML 等配置文件的
            // 分节注释全部使用单级 `#`，而真实文档大纲通常混用多级标题
            if headingLevels.count < 2 { headingPoints = min(headingPoints, 2) }
            score += headingPoints
            score += min(matchCount(text, regex: boldRegex), 2) * 2
        }

        score += min(matchCount(text, regex: blockquoteRegex), 2) * 2

        let bullets = matchCount(text, regex: bulletListRegex)
        if bullets >= 2 { score += 3 }
        let orderedItems = matchCount(text, regex: orderedListRegex)
        if orderedItems >= 2 { score += 3 }

        score += min(matchCount(text, regex: inlineCodeRegex), 3)

        return score >= 5
    }

    private static func isCodeFenceLine(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("```") { return true }
        if t.hasPrefix("~~~") {
            let nonTildes = t.drop(while: { $0 == "~" })
            return nonTildes.isEmpty || nonTildes.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" })
        }
        return false
    }

    /// 校验是否为管道表格分隔行 `| ------ | :---: |`
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

    /// 校验是否为 ATX 标题（1-6 个 `#` 后跟随空白字符）
    private static func isHeadingLine(_ line: String) -> Bool {
        headingLevel(line) != nil
    }

    /// 返回 ATX 标题级别（1-6），非标题行返回 nil
    private static func headingLevel(_ line: String) -> Int? {
        guard let regex = headingLineRegex,
              regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
        else { return nil }
        let level = line.drop(while: { $0 == " " }).prefix(while: { $0 == "#" }).count
        return (1...6).contains(level) ? level : nil
    }

    // MARK: - 正则匹配辅助函数

    private static func hasMatch(_ text: String, regex: NSRegularExpression?) -> Bool {
        guard let regex else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return regex.numberOfMatches(in: text, range: range) > 0
    }

    private static func matchCount(_ text: String, regex: NSRegularExpression?) -> Int {
        guard let regex else { return 0 }
        let range = NSRange(text.startIndex..., in: text)
        return regex.numberOfMatches(in: text, range: range)
    }

    private static func hasMatch(_ text: String, _ pattern: String, caseInsensitive: Bool = false) -> Bool {
        var options: NSRegularExpression.Options = [.anchorsMatchLines]
        if caseInsensitive { options.insert(.caseInsensitive) }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return regex.numberOfMatches(in: text, range: range) > 0
    }

    private static func matchCount(_ text: String, _ pattern: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return 0 }
        let range = NSRange(text.startIndex..., in: text)
        return regex.numberOfMatches(in: text, range: range)
    }
}

// MARK: - Language Enum

enum CodeLanguage: String, CaseIterable {
    case swift, python, javascript, typescript, java, kotlin
    case go, rust, html, css, xml, json, yaml, sql, shell, markdown, vue
    case c, cpp, csharp, objectivec
    case ruby, php, lua, dart, scala, perl
    case dockerfile, powershell, diff, makefile
    case unknown

    /// Map highlight.js language identifier to CodeLanguage.
    static func fromHighlightJS(_ name: String) -> CodeLanguage? {
        HLJS_MAP[name]
    }

    var displayName: String {
        switch self {
        case .swift: "Swift"
        case .python: "Python"
        case .javascript: "JavaScript"
        case .typescript: "TypeScript"
        case .java: "Java"
        case .kotlin: "Kotlin"
        case .go: "Go"
        case .rust: "Rust"
        case .html: "HTML"
        case .css: "CSS"
        case .sql: "SQL"
        case .shell: "Shell/Bash"
        case .xml: "XML"
        case .json: "JSON"
        case .yaml: "YAML"
        case .markdown: "Markdown"
        case .vue: "Vue"
        case .c: "C"
        case .cpp: "C++"
        case .csharp: "C#"
        case .objectivec: "Obj-C"
        case .ruby: "Ruby"
        case .php: "PHP"
        case .lua: "Lua"
        case .dart: "Dart"
        case .scala: "Scala"
        case .perl: "Perl"
        case .dockerfile: "Dockerfile"
        case .powershell: "PowerShell"
        case .diff: "Diff"
        case .makefile: "Makefile"
        case .unknown: "Auto"
        }
    }

    /// Languages available in the manual picker.
    static let pickerChoices: [CodeLanguage] = [
        .swift, .kotlin, .java, .python,
        .c, .cpp, .csharp, .objectivec,
        .javascript, .typescript, .go, .rust,
        .ruby, .php, .lua, .dart, .scala, .perl,
        .html, .xml, .css, .json, .yaml, .sql,
        .shell, .powershell, .dockerfile, .makefile,
        .markdown, .diff, .vue,
    ]

    var fileExtension: String {
        switch self {
        case .swift: "swift"
        case .python: "py"
        case .javascript: "js"
        case .typescript: "ts"
        case .java: "java"
        case .kotlin: "kt"
        case .go: "go"
        case .rust: "rs"
        case .html: "html"
        case .css: "css"
        case .sql: "sql"
        case .shell: "sh"
        case .xml: "xml"
        case .json: "json"
        case .yaml: "yml"
        case .markdown: "md"
        case .vue: "vue"
        case .c: "c"
        case .cpp: "cpp"
        case .csharp: "cs"
        case .objectivec: "m"
        case .ruby: "rb"
        case .php: "php"
        case .lua: "lua"
        case .dart: "dart"
        case .scala: "scala"
        case .perl: "pl"
        case .dockerfile: "dockerfile"
        case .powershell: "ps1"
        case .diff: "diff"
        case .makefile: "makefile"
        case .unknown: "txt"
        }
    }

    /// highlight.js language name for this CodeLanguage.
    var hljsName: String {
        switch self {
        case .shell: "bash"
        case .cpp: "cpp"
        case .csharp: "csharp"
        case .objectivec: "objectivec"
        default: rawValue
        }
    }

    // MARK: - highlight.js name → CodeLanguage mapping

    private static let HLJS_MAP: [String: CodeLanguage] = [
        "c": .c,
        "cpp": .cpp,
        "csharp": .csharp,
        "objectivec": .objectivec,
        "swift": .swift,
        "python": .python,
        "python-repl": .python,
        "javascript": .javascript,
        "typescript": .typescript,
        "java": .java,
        "kotlin": .kotlin,
        "go": .go,
        "rust": .rust,
        "html": .html,
        "xml": .xml,
        "css": .css,
        "json": .json,
        "yaml": .yaml,
        "sql": .sql,
        "bash": .shell,
        "shell": .shell,
        "markdown": .markdown,
        "ruby": .ruby,
        "php": .php,
        "php-template": .php,
        "lua": .lua,
        "dart": .dart,
        "scala": .scala,
        "perl": .perl,
        "dockerfile": .dockerfile,
        "powershell": .powershell,
        "diff": .diff,
        "makefile": .makefile,
    ]
}
