//
//  TemplateActions.swift
//  PasteMemo
//
//  Created by mao.tao on 2026/09/21.
//

import AppKit
import Foundation
import SwiftData

/// 模板执行与动作调度器，集中管理模板文本渲染、剪贴板写入与使用记录更新
@MainActor
enum TemplateActions {
    /// 剪贴板文本的短缓存（按 changeCount）：同一个 changeCount 内复用上一次读取，
    /// 保证模板预览与最终粘贴看到的是同一份 `{{clipboard}}` 值，面板悬停期间剪贴板
    /// 被别处改写也不会出现「所见非所得」；剪贴板发生变化时自动失效重新读取。
    private static var clipboardSnapshot: (changeCount: Int, text: String)?

    /// 获取当前剪贴板纯文本内容（带短缓存保护）
    static func currentClipboardText() -> String {
        let pasteboard = NSPasteboard.general
        if let snapshot = clipboardSnapshot, snapshot.changeCount == pasteboard.changeCount {
            return snapshot.text
        }
        let text = pasteboard.string(forType: .string) ?? ""
        clipboardSnapshot = (pasteboard.changeCount, text)
        return text
    }

    /// 根据当前个人资料配置与剪贴板快照，渲染模板内容
    static func renderedText(_ template: TemplateSnippet, fills: [String: String] = [:]) -> String {
        TemplateRenderer.render(
            template.content,
            context: TemplateContext(
                name: UserDefaults.standard.string(forKey: "templateProfileName") ?? "",
                project: UserDefaults.standard.string(forKey: "templateProjectName") ?? "",
                clipboard: currentClipboardText()
            ),
            fills: fills
        )
    }

    /// 复制渲染文本并标记 lastUsedAt。返回渲染结果，供粘贴回写路径复用同一份值。
    @discardableResult
    static func copy(_ template: TemplateSnippet, fills: [String: String] = [:]) -> String {
        let text = renderedText(template, fills: fills)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        pasteboard.markAsPasteMemoWrite()
        ClipboardManager.shared.lastChangeCount = pasteboard.changeCount
        template.lastUsedAt = Date()
        try? template.modelContext?.save()
        ToastCenter.shared.show(ToastDescriptor(message: L10n.tr("action.copied"), icon: .success))
        return text
    }
}
