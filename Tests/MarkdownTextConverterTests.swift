//
//  MarkdownTextConverterTests.swift
//  PasteMemoTests
//
//  作者：mao.tao
//

import Testing
@testable import PasteMemo

@Suite("MarkdownTextConverter 转换器测试")
struct MarkdownTextConverterTests {

    // MARK: - Markdown 转纯文本

    @Test("剥离标题符号，保留标题正文")
    func headings() {
        let input = "# Title\n\n## Section\n\n### Sub"
        #expect(MarkdownTextConverter.toPlainText(input) == "Title\n\nSection\n\nSub")
    }

    @Test("剥离粗体、斜体、删除线、行内代码与下划线标记")
    func inlineMarkers() {
        let input = "**bold** and *italic* and ~~struck~~ and `code` and __ubold__"
        #expect(MarkdownTextConverter.toPlainText(input) == "bold and italic and struck and code and ubold")
    }

    @Test("超链接保留文本；文本与链接一致时保留链接")
    func links() {
        #expect(MarkdownTextConverter.toPlainText("See [docs](https://example.com) here") == "See docs here")
        #expect(MarkdownTextConverter.toPlainText("[https://example.com](https://example.com)") == "https://example.com")
    }

    @Test("移除图片标记")
    func images() {
        let input = "Before\n\n![logo](https://example.com/logo.png)\n\nAfter"
        #expect(MarkdownTextConverter.toPlainText(input) == "Before\n\n\nAfter")
    }

    @Test("保留代码块内容并剥离首尾反引号栅栏行")
    func fencedCode() {
        let input = "Intro\n\n```swift\nlet x = 1 ** 2\n```\n\nOutro"
        #expect(MarkdownTextConverter.toPlainText(input) == "Intro\n\nlet x = 1 ** 2\n\nOutro")
    }

    @Test("代码块内部排版标记不被转义或剥离")
    func fencedCodeProtected() {
        let input = "```\n**not bold** [link](url) # heading\n```"
        #expect(MarkdownTextConverter.toPlainText(input) == "**not bold** [link](url) # heading")
    }

    @Test("行内代码内容不受强调符号剥离影响")
    func inlineCodeProtected() {
        #expect(MarkdownTextConverter.toPlainText("run `a *b* c` now") == "run a *b* c now")
    }

    @Test("剥离引用块前缀")
    func blockquotes() {
        #expect(MarkdownTextConverter.toPlainText("> quoted text") == "quoted text")
        #expect(MarkdownTextConverter.toPlainText(">> nested") == "nested")
    }

    @Test("保留有序列表编号结构")
    func orderedList() {
        let input = "1. first\n2. second\n3. third"
        #expect(MarkdownTextConverter.toPlainText(input) == input)
    }

    @Test("保留无序列表符号结构")
    func unorderedList() {
        let input = "- one\n- two\n- three"
        #expect(MarkdownTextConverter.toPlainText(input) == input)
    }

    @Test("移除表格分隔线，将数据行转换为制表符分隔且清理行内格式")
    func tables() {
        let input = "| **Name** | [Score](https://example.com) |\n|------|-------|\n| Ann  | `3`     |"
        #expect(MarkdownTextConverter.toPlainText(input) == "Name\tScore\nAnn\t3")
    }

    @Test("剥离 YAML Frontmatter 元数据块")
    func frontmatter() {
        let input = "---\ntitle: Doc\n---\n\n# Doc\n\nBody"
        #expect(MarkdownTextConverter.toPlainText(input) == "Doc\n\nBody")
    }

    @Test("不误伤下划线命名变量及乘法算式")
    func noFalsePositives() {
        #expect(MarkdownTextConverter.toPlainText("some_var_name stays") == "some_var_name stays")
        #expect(MarkdownTextConverter.toPlainText("2 * 3 * 4 = 24") == "2 * 3 * 4 = 24")
    }

    @Test("普通纯文本原样保留不改变")
    func plainTextUnchanged() {
        let input = "普通文本第一行\n第二行没有语法"
        #expect(MarkdownTextConverter.toPlainText(input) == input)
    }

    @Test("结构化问答排版文本正确转换且格式完好")
    func structuredAnswer() {
        let input = """
        ## 解决方案

        步骤如下：

        1. 安装依赖
        2. 运行脚本

        ```bash
        npm install
        ```

        参考[文档](https://example.com)获取详情。
        """
        let expected = """
        解决方案

        步骤如下：

        1. 安装依赖
        2. 运行脚本

        npm install

        参考文档获取详情。
        """
        #expect(MarkdownTextConverter.toPlainText(input) == expected)
    }

    @Test("引用式链接保留文本标签")
    func referenceLinks() {
        #expect(MarkdownTextConverter.toPlainText("see [the docs][1] now") == "see the docs now")
    }

    @Test("还原 Markdown 标点符号转义")
    func escapes() {
        #expect(MarkdownTextConverter.toPlainText("literal \\*not emphasis\\*") == "literal *not emphasis*")
    }

    // MARK: - 删除空行测试

    @Test("删除文本中的空行")
    func removesEmptyLines() {
        #expect(MarkdownTextConverter.removeEmptyLines("a\n\nb\n\n\nc") == "a\nb\nc")
    }

    @Test("删除仅含空白字符的空行")
    func removesWhitespaceLines() {
        #expect(MarkdownTextConverter.removeEmptyLines("a\n   \t\nb") == "a\nb")
    }

    @Test("删除首尾的空行")
    func removesEdgeLines() {
        #expect(MarkdownTextConverter.removeEmptyLines("\n\na\n\n") == "a")
    }

    @Test("空输入保持为空")
    func emptyInput() {
        #expect(MarkdownTextConverter.removeEmptyLines("") == "")
        #expect(MarkdownTextConverter.removeEmptyLines("\n\n\n") == "")
    }

    @Test("无空行的文本保持不变")
    func noEmptyLinesUnchanged() {
        #expect(MarkdownTextConverter.removeEmptyLines("a\nb\nc") == "a\nb\nc")
    }
}
