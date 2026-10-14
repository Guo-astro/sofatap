import SwiftUI
import UIKit

// UIKit text storage and delegate calls, with no UIApplicationMain, window,
// keyboard focus or OS input. The render hook exercises the interval after
// UIKit changes its text/selection but before it calls textViewDidChange.
@MainActor
private final class DraftFixture: NSObject, UITextViewDelegate {
    var text: String
    var composing = false
    var focused = false
    var beforeRender: (() -> Void)?
    var renderDuringPublication = false
    var edits: [(String, NSRange, Bool)] = []
    var emptyBackspaces = 0
    let view = NativeDraftEditor.TextView()
    var coordinator: NativeDraftEditor.Coordinator!

    init(_ text: String = "", control: NativeDraftEditor.Control? = nil) {
        self.text = text
        super.init()
        let editor = NativeDraftEditor(
            text: Binding(get: { self.text }, set: {
                self.text = $0
                if self.renderDuringPublication { self.coordinator.synchronizeText(self.view) }
            }),
            composing: Binding(get: { self.composing }, set: { self.composing = $0 }),
            isFocused: Binding(get: { self.focused }, set: { self.focused = $0 }), disabled: false,
            onEdit: control == nil ? nil : { [weak self] text, selection, marked in
                self?.edits.append((text, selection, marked))
            },
            control: control,
            onEmptyBackspace: { [weak self] in self?.emptyBackspaces += 1 })
        coordinator = editor.makeCoordinator()
        coordinator.textView = view
        coordinator.attachControl(control)
        coordinator.synchronizeText(view)
        view.selectedRange = NSRange(location: text.utf16.count, length: 0)
        view.delegate = self
    }

    func render() { coordinator.synchronizeText(view) }
    func textViewDidChangeSelection(_ textView: UITextView) {
        coordinator.textViewDidChangeSelection(textView)
        beforeRender?()
        render()
    }
    func textViewDidChange(_ textView: UITextView) { coordinator.textViewDidChange(textView) }
}

@main
struct NativeDraftEditorTests {
    @MainActor static func main() {
        var passed = 0
        func check(_ name: String, _ condition: @autoclosure () -> Bool) {
            guard condition() else {
                fputs("FAIL: \(name)\n", stderr)
                exit(1)
            }
            passed += 1
        }

        let interleaved = DraftFixture("实")
        interleaved.view.insertText("测")
        check("render before didChange preserves the newly inserted character", interleaved.text == "实测" && interleaved.view.text == "实测")

        let unicode = DraftFixture()
        let sample = "Sofatap Windows 实测\n中文・日本語・emoji 🛋️"
        for scalar in sample.unicodeScalars { unicode.view.insertText(String(scalar)) }
        check("interleaved renders preserve mixed Unicode, newline and variation selector", unicode.text == sample && unicode.view.text == sample)
        unicode.view.selectedRange = NSRange(location: 16, length: 2)
        unicode.render()
        check("unrelated renders preserve UTF-16 selection", unicode.view.selectedRange == NSRange(location: 16, length: 2))
        unicode.view.insertText("测试")
        check("replacement of selected characters reaches the binding", unicode.text == sample.replacingOccurrences(of: "实测", with: "测试"))

        let deletion = DraftFixture("中文 🛋️")
        deletion.view.deleteBackward()
        check("interleaved render does not restore a deleted emoji grapheme", deletion.text == "中文 " && deletion.view.text == "中文 ")
        deletion.view.selectedRange = NSRange(location: 0, length: 2)
        deletion.view.deleteBackward()
        check("selection deletion reaches the binding without restoring old text", deletion.text == " " && deletion.view.text == " ")

        let emptyKeyboard = DraftFixture()
        emptyKeyboard.view.deleteBackward()
        check("native empty Backspace reports one remote-key intent", emptyKeyboard.emptyBackspaces == 1)
        emptyKeyboard.view.insertText("草稿")
        emptyKeyboard.view.deleteBackward(); emptyKeyboard.view.deleteBackward()
        check("deleting unsent characters including the last one is local only", emptyKeyboard.text.isEmpty && emptyKeyboard.emptyBackspaces == 1)
        emptyKeyboard.view.deleteBackward()
        check("the next empty Backspace reports exactly one new intent", emptyKeyboard.emptyBackspaces == 2)
        emptyKeyboard.coordinator.parent.liveEditing = true
        emptyKeyboard.view.deleteBackward()
        check("empty live snapshot never emits a second OS Backspace", emptyKeyboard.emptyBackspaces == 2)
        emptyKeyboard.coordinator.parent.liveEditing = false
        emptyKeyboard.composing = true
        emptyKeyboard.view.deleteBackward()
        check("composition suppresses empty Backspace intent", emptyKeyboard.emptyBackspaces == 2)
        emptyKeyboard.composing = false
        emptyKeyboard.coordinator.parent.disabled = true
        emptyKeyboard.view.deleteBackward()
        check("disabled editor suppresses empty Backspace intent", emptyKeyboard.emptyBackspaces == 2)
        emptyKeyboard.coordinator.parent.disabled = false
        emptyKeyboard.text = "尚未渲染的草稿"
        emptyKeyboard.view.deleteBackward()
        check("an unpublished model draft cannot delete remote text", emptyKeyboard.emptyBackspaces == 2)
        emptyKeyboard.coordinator.textView = nil
        emptyKeyboard.view.deleteBackward()
        check("a detached native editor cannot issue a remote key", emptyKeyboard.emptyBackspaces == 2)

        let clear = DraftFixture("待清空的草稿")
        clear.text = ""
        clear.render()
        check("explicit model clear empties the editor", clear.view.text.isEmpty && clear.text.isEmpty)
        check("clear clamps selection", clear.view.selectedRange == NSRange(location: 0, length: 0))

        let voice = DraftFixture("原始草稿")
        voice.text = "原始草稿\n语音追加：你好 🛋️"
        voice.render()
        check("external speech result replaces the editor without loss", voice.view.text == voice.text)
        check("external replacement preserves a valid insertion point", voice.view.selectedRange == NSRange(location: 4, length: 0))
        voice.text = "最终"
        voice.render()
        check("shorter external speech correction clamps the cursor", voice.view.text == "最终" && voice.view.selectedRange == NSRange(location: 2, length: 0))

        let ime = DraftFixture("前缀 ")
        ime.view.setMarkedText("shice", selectedRange: NSRange(location: 5, length: 0))
        check("marked composition remains intact across render", ime.view.markedTextRange != nil && ime.composing && ime.text == "前缀 shice")
        ime.render()
        check("unrelated render does not destroy the marked range", ime.view.markedTextRange != nil)
        ime.view.insertText("实测")
        check("IME candidate commits the full text", ime.view.text == "前缀 实测" && ime.text == "前缀 实测")
        check("IME completion updates composing state", !ime.composing && ime.view.markedTextRange == nil)

        let deferredClear = DraftFixture("保留 ")
        deferredClear.view.setMarkedText("shice", selectedRange: NSRange(location: 5, length: 0))
        deferredClear.text = ""
        deferredClear.render()
        check("external clear waits for active marked text", deferredClear.view.markedTextRange != nil && deferredClear.text.isEmpty)
        deferredClear.view.insertText("实测")
        check("later local candidate callback does not swallow explicit clear", deferredClear.view.text.isEmpty && deferredClear.text.isEmpty && !deferredClear.composing)

        let deferredVoice = DraftFixture()
        deferredVoice.view.setMarkedText("ceshi", selectedRange: NSRange(location: 5, length: 0))
        deferredVoice.text = "第一次语音"
        deferredVoice.render()
        deferredVoice.text = "最终语音 🛋️"
        deferredVoice.render()
        deferredVoice.view.unmarkText()
        deferredVoice.coordinator.textViewDidChangeSelection(deferredVoice.view)
        check("latest external update survives unmark without didChange", deferredVoice.view.text == "最终语音 🛋️" && deferredVoice.text == "最终语音 🛋️")

        let cancelledReplacement = DraftFixture()
        cancelledReplacement.view.setMarkedText("ce", selectedRange: NSRange(location: 2, length: 0))
        cancelledReplacement.text = ""
        cancelledReplacement.render()
        cancelledReplacement.text = "ce"
        cancelledReplacement.render()
        cancelledReplacement.view.insertText("测")
        check("restoring the model cancels an obsolete queued clear", cancelledReplacement.text == "测" && cancelledReplacement.view.text == "测")

        let concurrentClear = DraftFixture("实")
        concurrentClear.beforeRender = {
            concurrentClear.beforeRender = nil
            concurrentClear.text = ""
        }
        concurrentClear.view.insertText("测")
        check("explicit clear wins during a native edit callback", concurrentClear.text.isEmpty && concurrentClear.view.text.isEmpty)

        let endEditing = DraftFixture("原文")
        endEditing.view.delegate = nil
        endEditing.view.text = "尚未通知的最后一字测"
        endEditing.focused = true
        endEditing.coordinator.textViewDidEndEditing(endEditing.view)
        check("end editing flushes the final native value", endEditing.text == "尚未通知的最后一字测" && !endEditing.focused && !endEditing.composing)

        let publication = DraftFixture("实")
        publication.renderDuringPublication = true
        publication.view.insertText("测")
        check("binding publication cannot recursively overwrite the edit", publication.text == "实测" && publication.view.text == "实测")

        let sendControl = NativeDraftEditor.Control()
        let pendingVoice = DraftFixture("原文 ", control: sendControl)
        pendingVoice.view.delegate = nil
        pendingVoice.view.insertText("语音追加 🛋️")
        let nativeVoice = pendingVoice.view.text!
        let nativeSelection = pendingVoice.view.selectedRange
        check("fixture delays delegate publication before Send", pendingVoice.text == "原文 " && nativeVoice != pendingVoice.text)
        check("Send flush publishes the latest native voice append", sendControl.flushForSend() && pendingVoice.text == nativeVoice)
        check("Send flush publishes the matching native selection atomically", pendingVoice.edits.last?.0 == nativeVoice && pendingVoice.edits.last?.1 == nativeSelection && pendingVoice.edits.last?.2 == false)

        let markedControl = NativeDraftEditor.Control()
        let pendingIME = DraftFixture("前缀 ", control: markedControl)
        pendingIME.view.delegate = nil
        pendingIME.view.setMarkedText("shice", selectedRange: NSRange(location: 5, length: 0))
        check("Send refuses provisional IME and retains the marked range", !markedControl.flushForSend() && pendingIME.view.markedTextRange != nil)
        check("refused Send does not publish a provisional edit", pendingIME.text == "前缀 " && pendingIME.edits.isEmpty)
        pendingIME.view.insertText("实测")
        check("an explicit keyboard commit can subsequently flush for Send", markedControl.flushForSend() && pendingIME.text == "前缀 实测" && pendingIME.edits.last?.2 == false)

        let clearControl = NativeDraftEditor.Control()
        let clearBeforeSend = DraftFixture("旧草稿", control: clearControl)
        clearBeforeSend.view.delegate = nil
        clearBeforeSend.view.insertText("最后一字")
        clearBeforeSend.text = ""
        check("explicit model clear wins over an unpublished native edit at Send", clearControl.flushForSend() && clearBeforeSend.text.isEmpty && clearBeforeSend.view.text.isEmpty)
        check("clear flush publishes empty text and valid selection", clearBeforeSend.edits.last?.0 == "" && clearBeforeSend.edits.last?.1 == NSRange(location: 0, length: 0))

        let detachedControl = NativeDraftEditor.Control()
        check("an unattached Send control cannot report a successful flush", !detachedControl.flushForSend())
        let oldEditor = DraftFixture("旧实例", control: detachedControl)
        let newEditor = DraftFixture("新实例", control: detachedControl)
        oldEditor.coordinator.attachControl(nil)
        newEditor.view.delegate = nil
        newEditor.view.insertText("输入")
        check("old editor teardown cannot detach the current Send control", detachedControl.flushForSend() && newEditor.text == "新实例输入")
        newEditor.coordinator.attachControl(nil)
        check("current editor teardown detaches Send safely", !detachedControl.flushForSend())

        print("Native draft editor: \(passed) UIKit checks passed without windows or input injection")
    }
}
