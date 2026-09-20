import Testing
@testable import PasteMemo

@Suite("CodeDetector Tests")
@MainActor
struct CodeDetectorTests {

    // MARK: - JSON

    @Test("Complete JSON object detected as JSON")
    func completeJSON() {
        let text = """
        {"name": "test", "value": 42, "active": true}
        """
        #expect(CodeDetector.detectLanguage(text) == .json)
    }

    @Test("Complete JSON array detected as JSON")
    func completeJSONArray() {
        let text = """
        [{"id": 1, "name": "foo"}, {"id": 2, "name": "bar"}]
        """
        #expect(CodeDetector.detectLanguage(text) == .json)
    }

    @Test("Pretty-printed JSON detected as JSON")
    func prettyJSON() {
        let text = """
        {
            "model": "deepseek-v3",
            "max_tokens": 8192,
            "messages": [
                {"role": "system", "content": "You are a helper"},
                {"role": "user", "content": "Hello"}
            ],
            "stream": true,
            "temperature": 0.7
        }
        """
        #expect(CodeDetector.detectLanguage(text) == .json)
    }

    @Test("JSON fragment not detected as JSON")
    func jsonFragment() {
        let text = """
        "model": "deepseek-v3",
        "max_tokens": 8192,
        "stream": true
        """
        // Invalid JSON (not parseable) → must NOT be detected as JSON
        let result = CodeDetector.detectLanguage(text)
        #expect(result != .json, "JSON fragment should not be detected as JSON, got: \(String(describing: result))")
    }

    // MARK: - Server Logs (should be nil / plain text)

    @Test("Server log with embedded JSON not detected as code")
    func serverLogWithJSON() {
        let text = """
        [server] [2026-03-24 18:45:18.743] DEBUG 60278 --- [.volces.com/...] c.m.i.a.a.s.RedisChatStreamRegistry      : Completed chat stream: chatId=70f63f567b5f427381f60eef3c1893a8
        [server] [2026-03-24 18:45:18.763] DEBUG 60278 --- [.volces.com/...] c.m.i.a.a.s.RedisChatStreamRegistry      : Completed chat stream: chatId=c8416e0297944129a8551014608987cd
        [server] [2026-03-24 18:45:18.849]  INFO 60278 --- [.volces.com/...] c.m.i.a.b.ai.service.DeepSeekAiService   : Updated chatlog with id: 69c26b3e0b2e19562566af6d, status: FAIL
        [server] [2026-03-24 18:45:18.850] ERROR 60278 --- [tcher-worker-17] c.m.i.a.b.ai.service.DeepSeekAiService   : streamChatSync 完成但结果为空，可能 AI 调用失败
        """
        let result = CodeDetector.detectLanguage(text)
        #expect(result == nil, "Server log should not be detected as code, got: \(String(describing: result))")
    }

    @Test("Server log with stack trace not detected as code")
    func serverLogWithStackTrace() {
        let text = """
        [server] java.net.ConnectException: Failed to connect to /127.0.0.1:7891
        [server]        at okhttp3.internal.connection.RealConnection.connectSocket(RealConnection.kt:297)
        [server]        at okhttp3.internal.connection.RealConnection.connectTunnel(RealConnection.kt:261)
        [server]        at okhttp3.internal.connection.RealConnection.connect(RealConnection.kt:201)
        [server] Caused by: java.net.ConnectException: Connection refused
        [server]        at java.base/sun.nio.ch.Net.pollConnect(Native Method)
        [server]        at java.base/sun.nio.ch.NioSocketImpl.connect(NioSocketImpl.java:592)
        [server]        ... 19 common frames omitted
        """
        let result = CodeDetector.detectLanguage(text)
        #expect(result == nil, "Server log with stack trace should not be detected as code, got: \(String(describing: result))")
    }

    @Test("Mixed server log with JSON request body not detected as code")
    func serverLogMixed() {
        let text = """
        [server] [2026-03-24 18:45:19.204] DEBUG 58752 --- [tcher-worker-19] c.m.i.a.b.ai.service.DeepSeekAiService   : ### Chat Request: {"model":"deepseek-v3-250324","max_tokens":8192,"messages":[{"role":"system","content":"你是专家"}],"stream":true,"temperature":0.7}
        [server] [2026-03-24 18:45:19.204] DEBUG 58752 --- [tcher-worker-19] c.m.i.a.b.ai.service.DeepSeekAiService   : ### Chat Request URL: https://ark.cn-beijing.volces.com/api/v3/chat/completions
        [server] [2026-03-24 18:45:19.245] DEBUG 58752 --- [tcher-worker-19] c.m.i.a.a.s.RedisChatStreamRegistry      : Registered chat stream: chatId=200283390c124dd484d54256ce9cfd41
        [server] [2026-03-24 18:45:19.267]  INFO 58752 --- [tcher-worker-19] c.m.i.a.b.ai.service.DeepSeekAiService   : Pre-saved chatlog with id: 69c26b3f0b2e19562566af78
        """
        let result = CodeDetector.detectLanguage(text)
        #expect(result == nil, "Mixed server log should not be detected as code, got: \(String(describing: result))")
    }

    // MARK: - Actual Code (should be detected correctly)

    @Test("Swift code detected as Swift")
    func swiftCode() {
        let text = """
        import Foundation

        @Observable
        class UserViewModel {
            var name = ""
            var isLoading = false

            func fetchUser() async {
                guard let url = URL(string: "https://api.example.com") else { return }
            }
        }
        """
        #expect(CodeDetector.detectLanguage(text) == .swift)
    }

    @Test("Java code detected as Java")
    func javaCode() {
        let text = """
        package com.example.app;

        import java.util.List;
        import java.util.ArrayList;

        public class Main {
            public static void main(String[] args) {
                List<String> items = new ArrayList<>();
                items.add("Hello");
                System.out.println(items.get(0));
            }

            @Override
            public String toString() {
                return "Main";
            }
        }
        """
        let result = CodeDetector.detectLanguage(text)
        #expect(result == .java || result == .csharp, "Java-like code, got: \(String(describing: result))")
    }

    @Test("Kotlin code detected as Kotlin")
    func kotlinCode() {
        let text = """
        data class User(val name: String, val age: Int)

        fun main() {
            val user = User("Alice", 30)
            println(user.name)
        }
        """
        #expect(CodeDetector.detectLanguage(text) == .kotlin)
    }

    @Test("Python code detected as Python")
    func pythonCode() {
        let text = """
        from dataclasses import dataclass

        @dataclass
        class User:
            name: str
            age: int

        def greet(self):
            print(f"Hello {self.name}")
        """
        #expect(CodeDetector.detectLanguage(text) == .python)
    }

    @Test("Shell script detected as Shell")
    func shellCode() {
        let text = """
        #!/bin/bash
        if [ -f "$FILE" ]; then
            echo "File exists"
            export PATH="/usr/local/bin:$PATH"
        fi
        """
        #expect(CodeDetector.detectLanguage(text) == .shell)
    }

    @Test("HTML detected as HTML")
    func htmlCode() {
        let text = """
        <!DOCTYPE html>
        <html>
        <head><title>Test</title></head>
        <body><div class="main">Hello</div></body>
        </html>
        """
        #expect(CodeDetector.detectLanguage(text) == .html)
    }

    @Test("XML detected as XML")
    func xmlCode() {
        let text = """
        <?xml version="1.0" encoding="UTF-8"?>
        <root>
            <item id="1">Hello</item>
            <item id="2">World</item>
        </root>
        """
        #expect(CodeDetector.detectLanguage(text) == .xml)
    }

    @Test("SQL detected as SQL")
    func sqlCode() {
        let text = """
        SELECT u.name, u.email
        FROM users u
        LEFT JOIN orders o ON u.id = o.user_id
        WHERE u.active = true
        ORDER BY u.name
        """
        #expect(CodeDetector.detectLanguage(text) == .sql)
    }

    @Test("Vue SFC detected as Vue")
    func vueSFC() {
        let text = """
        <script setup lang="ts">
          import { ref } from 'vue'
          const count = ref(0)
        </script>

        <template>
          <div>
            <button @click="count++">{{ count }}</button>
          </div>
        </template>

        <style scoped>
          div { padding: 20px; }
        </style>
        """
        #expect(CodeDetector.detectLanguage(text) == .vue)
    }

    @Test("Vue SFC with v-for detected as Vue")
    func vueSFCWithDirectives() {
        let text = """
        <template>
          <ul>
            <li v-for="item in items" :key="item.id">{{ item.name }}</li>
            <li v-if="loading">Loading...</li>
          </ul>
        </template>
        """
        #expect(CodeDetector.detectLanguage(text) == .vue)
    }

    @Test("Full Vue SFC with large CSS section detected as Vue")
    func vueSFCLargeCSS() {
        let text = """
        <script setup lang="ts">
          import { useRouter } from 'vue-router'
          import { computed } from 'vue'

          const router = useRouter()
          const handleGetStarted = () => {
            router.push('/insight')
          }
        </script>

        <template>
          <div class="home-page">
            <section class="hero">
              <button @click="handleGetStarted" class="btn-primary">开始使用</button>
            </section>
            <section class="stats-bar">
              <div v-for="(stat, index) in stats" :key="index" class="stat-item">
                <span>{{ stat.value }}</span>
              </div>
            </section>
          </div>
        </template>

        <style scoped>
          .home-page { display: flex; flex-direction: column; min-height: calc(100vh - 120px); }
          .hero { flex: 1; display: flex; align-items: center; justify-content: center; }
          .btn-primary { background-color: var(--color-button-bg); padding: 14px 32px; border-radius: 100px; }
          .stats-bar { width: 100%; padding: 24px 40px; border-top: 1px solid var(--color-border-light); }
          .stat-item { display: flex; flex-direction: column; align-items: center; }
          @media (max-width: 768px) { .hero { padding: 0 16px; } .stat-item { width: 33%; } }
        </style>
        """
        #expect(CodeDetector.detectLanguage(text) == .vue)
    }

    @Test("JSON with URLs detected as JSON, not Perl")
    func jsonWithURLs() {
        let text = """
        {
          "mcpServers": {
            "mongodb": {
              "command": "npx",
              "args": [
                "-y",
                "mcp-mongo-server",
                "mongodb://user:pass@host:27017/db"
              ]
            },
            "mariadb": {
              "command": "npx",
              "args": [
                "-y",
                "mcp-mysql-server",
                "mysql://root:123@host:3306/db"
              ]
            }
          }
        }
        """
        #expect(CodeDetector.detectLanguage(text) == .json)
    }

    // MARK: - C/C++/C#

    @Test("C code detected as C or C++")
    func cCode() {
        let text = """
        #include <stdio.h>

        int main() {
            printf("Hello, World!\\n");
            return 0;
        }
        """
        let result = CodeDetector.detectLanguage(text)
        #expect(result == .c || result == .cpp, "C code should be detected as C or C++, got: \\(String(describing: result))")
    }

    @Test("C# code detected as C#")
    func csharpCode() {
        let text = """
        using System;

        namespace MyApp {
            class Program {
                static void Main(string[] args) {
                    Console.WriteLine("Hello World");
                }
            }
        }
        """
        #expect(CodeDetector.detectLanguage(text) == .csharp)
    }

    @Test("TypeScript with object literal not detected as JSON")
    func typescriptNotJSON() {
        let text = """
        import { ModuleType } from '@/model/module-type'

        export const PromptCategories: Record<ModuleType, string[]> = {
          [ModuleType.PROJECT]: ['创建项目'],
          [ModuleType.INTERVIEW]: [
            '主Prompt',
            '用户痛点',
            '用户推荐',
          ],
        }
        """
        let result = CodeDetector.detectLanguage(text)
        #expect(result == .typescript, "TypeScript with import/export should be detected as TypeScript, got: \(String(describing: result))")
    }

    // MARK: - Plain Text (should NOT be detected as code)

    @Test("Plain Chinese text not detected as code")
    func plainChinese() {
        let text = "你好，这是一段普通的中文文本，不应该被识别为代码。"
        #expect(CodeDetector.detectLanguage(text) == nil)
    }

    @Test("Plain English text not detected as code")
    func plainEnglish() {
        let text = "This is a regular sentence that should not be detected as any programming language."
        #expect(CodeDetector.detectLanguage(text) == nil)
    }

    @Test("Markdown table detected as markdown")
    func markdownTable() {
        let text = """
        | 用户名 | 评分 | 评价 |
        |--------|------|------|
        | 张三   | 3    | 可信 |
        | 李四   | 4    | 不错 |
        """
        let result = CodeDetector.detectLanguage(text)
        #expect(result == .markdown, "Table should be markdown, got: \(String(describing: result))")
    }

    // MARK: - Markdown (structural detection; hljs scores typical markdown below
    // its relevance gate and sometimes prefers shell/kotlin — see isMarkdown)

    @Test("README with headings, lists and code fence detected as markdown")
    func markdownReadme() {
        let text = """
        # Project Title

        A short description of what this project does.

        ## Features

        - Fast clipboard history
        - Smart type detection
        - Keyboard shortcuts

        ## Installation

        ```bash
        brew install pastememo
        ```

        For more info see the [docs](https://example.com/docs).
        """
        #expect(CodeDetector.detectLanguage(text) == .markdown)
    }

    @Test("Chinese markdown document with code fence detected as markdown")
    func markdownChineseDoc() {
        let text = """
        # 使用指南

        这是一份中文说明文档。

        ## 功能列表

        - 剪贴板历史记录
        - 智能类型识别
        - 快捷键支持

        ## 安装步骤

        1. 打开终端
        2. 执行安装命令

        详细内容请参考[文档](https://example.com)。
        """
        #expect(CodeDetector.detectLanguage(text) == .markdown)
    }

    @Test("问答排版格式文本正确识别为 Markdown")
    func markdownQAAnswer() {
        let text = """
        Here's how to solve the problem:

        1. First, install the dependency
        2. Then run the setup script

        ```bash
        npm install && npm run setup
        ```

        That should fix the issue.
        """
        #expect(CodeDetector.detectLanguage(text) == .markdown)
    }

    @Test("Notes with bold, bullet list and blockquote detected as markdown")
    func markdownBoldListQuote() {
        let text = """
        **重要提醒**

        明天上午 10 点开会，请准时参加。

        - 准备好周报
        - 带上笔记本电脑

        > 注意：会议室改到 3 楼
        """
        #expect(CodeDetector.detectLanguage(text) == .markdown)
    }

    @Test("Headings-only document detected as markdown, not shell")
    func markdownHeadingsOnly() {
        let text = """
        # Title

        ## Section One

        Some intro text here.

        ### Subsection

        More details about the topic.
        """
        let result = CodeDetector.detectLanguage(text)
        #expect(result == .markdown, "Heading-heavy doc was misdetected as: \(String(describing: result))")
    }

    @Test("Prose with inline link and inline code detected as markdown, not kotlin")
    func markdownLinkAndCode() {
        let text = """
        Check out [this guide](https://example.com) for details.

        Also see *the docs* and `code` inline.
        """
        let result = CodeDetector.detectLanguage(text)
        #expect(result == .markdown, "Link prose was misdetected as: \(String(describing: result))")
    }

    @Test("Fenced code block alone detected as markdown")
    func markdownCodeFenceOnly() {
        let text = """
        ```python
        def hello():
            print("world")
        ```
        """
        #expect(CodeDetector.detectLanguage(text) == .markdown)
    }

    @Test("Bare bullet list not misdetected as a code language")
    func markdownBareBulletList() {
        let text = """
        - 第一项
        - 第二项
        - 第三项
        """
        let result = CodeDetector.detectLanguage(text)
        #expect(result == nil || result == .markdown,
                "Bare list must not be detected as a programming language, got: \(String(describing: result))")
    }

    @Test("Bare numbered steps not misdetected as a code language")
    func markdownBareNumberedSteps() {
        let text = """
        1. 打开设置
        2. 点击通用
        3. 选择关于本机
        """
        let result = CodeDetector.detectLanguage(text)
        #expect(result == nil || result == .markdown,
                "Numbered steps must not be detected as a programming language, got: \(String(describing: result))")
    }

    // MARK: - Markdown false-positive guards

    @Test("Ruby file with leading comments stays Ruby, not markdown")
    func rubyWithCommentsNotMarkdown() {
        let text = """
        # frozen_string_literal: true
        # This module handles user auth
        # It was added in v2.0
        require 'jwt'

        module Auth
          def tokenize(user)
            JWT.encode({id: user.id}, SECRET)
          end
        end
        """
        #expect(CodeDetector.detectLanguage(text) == .ruby)
    }

    @Test("C preprocessor lines are not markdown headings")
    func cIncludeNotMarkdownHeading() {
        let text = """
        #include <stdio.h>
        #include <stdlib.h>
        #define MAX 100

        int main() {
            printf("Hello, World!\\n");
            return 0;
        }
        """
        let result = CodeDetector.detectLanguage(text)
        #expect(result == .c || result == .cpp,
                "C with #include/#define must stay C/C++, got: \(String(describing: result))")
    }

    @Test("包含外链注释的 Swift 代码依然识别为 Swift 而非 Markdown")
    func swiftWithMarkdownLinkInComments() {
        let text = """
        // 详情请参考官方文档 [Swift Guide](https://swift.org/documentation)
        import Foundation

        struct UserManager {
            func fetchUser(id: Int) -> String {
                return "user_\(id)"
            }
        }
        """
        #expect(CodeDetector.detectLanguage(text) == .swift)
    }

    @Test("Dockerfile with section comments stays Dockerfile, not markdown")
    func dockerfileWithSectionCommentsNotMarkdown() {
        let text = """
        # Base image

        FROM node:20-alpine

        # Install dependencies

        COPY package*.json ./
        RUN npm ci

        # Start the app

        CMD ["node", "index.js"]
        """
        let result = CodeDetector.detectLanguage(text)
        #expect(result == .dockerfile,
                "Comment-sectioned Dockerfile must stay Dockerfile, got: \(String(describing: result))")
    }

    @Test("YAML with section comments stays YAML, not markdown")
    func yamlWithSectionCommentsNotMarkdown() {
        let text = """
        # Database settings

        host: localhost
        port: 5432

        # Cache settings

        redis:
          host: 127.0.0.1
          ttl: 300

        # Logging

        log_level: info
        """
        let result = CodeDetector.detectLanguage(text)
        #expect(result == .yaml,
                "Comment-sectioned YAML must stay YAML, got: \(String(describing: result))")
    }
}
