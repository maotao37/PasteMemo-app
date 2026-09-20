import Foundation
import Testing
@testable import PasteMemo

@Suite("Paste as file")
struct PasteAsFileTests {
    @Test("text and code clips become files with useful extensions")
    @MainActor func materializesTextAndCode() throws {
        let text = ClipItem(content: "hello\nworld", contentType: .text)
        let code = ClipItem(content: "print(\"hello\")", contentType: .code, codeLanguage: CodeLanguage.python.rawValue)

        let urls = ClipboardManager.shared.fileURLsForPaste([text, code])
        defer {
            if let first = urls.first {
                try? FileManager.default.removeItem(at: first.deletingLastPathComponent())
            }
        }

        #expect(urls.count == 2)
        #expect(urls[0].pathExtension == "txt")
        #expect(urls[1].pathExtension == "py")
        #expect(try String(contentsOf: urls[0], encoding: .utf8) == "hello\nworld")
        #expect(try String(contentsOf: urls[1], encoding: .utf8) == "print(\"hello\")")
    }

    @Test("raw images become image files without using the display placeholder")
    @MainActor func materializesRawImage() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let image = ClipItem(content: "[Image]", contentType: .image, imageData: png)

        let url = try #require(ClipboardManager.shared.fileURLsForPaste([image]).first)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        #expect(url.pathExtension == "png")
        #expect(try Data(contentsOf: url) == png)
    }

    @Test("existing file clips keep their original URL")
    @MainActor func reusesExistingFile() throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("pm-paste-as-file-\(UUID().uuidString).pdf")
        try Data("pdf".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let item = ClipItem(content: source.path, contentType: .document)
        let urls = ClipboardManager.shared.fileURLsForPaste([item])

        #expect(urls == [source])
    }

    @Test("临时文件名满足 temp_yyyymmddhh24miss_毫秒3位.ext 格式")
    func tempFilenameFormat() throws {
        // 传入已知时间戳测试格式
        let testDate = Date(timeIntervalSince1970: 1726837875.123)
        let filename = ClipboardManager.generateTempFileName(fileExtension: "txt", date: testDate)

        #expect(filename.hasPrefix("temp_"))
        #expect(filename.hasSuffix(".txt"))

        // 匹配 temp_ 年月日时分秒(14位数字) _ 毫秒(3位数字) . 扩展名
        let regex = try NSRegularExpression(pattern: #"^temp_\d{14}_\d{3}\.txt$"#)
        let matches = regex.matches(in: filename, range: NSRange(location: 0, length: filename.utf16.count))
        #expect(matches.count == 1)
    }
}
