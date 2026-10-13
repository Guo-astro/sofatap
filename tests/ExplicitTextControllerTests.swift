import Foundation

@MainActor
private final class ExplicitFixture {
    struct Frame {
        let type: String
        let fields: [String: Any]
        var reply: (([String: Any]) -> Void)?
    }
    var frames: [Frame] = []
    let defaults: UserDefaults?
    init(defaults: UserDefaults? = nil) { self.defaults = defaults }
    lazy var model = ControllerModel(testLiveSend: { [unowned self] type, fields, reply in
        frames.append(Frame(type: type, fields: fields, reply: reply))
    }, draftDefaults: defaults)
    func reply(_ index: Int, _ result: [String: Any] = ["ok": true]) {
        guard let callback = frames[index].reply else { fatalError("Duplicate reply") }
        frames[index].reply = nil
        callback(result)
    }
    func fallback() {
        model.openTextEditor()
        reply(0, ["ok": false, "error": "live_text_unsupported"])
    }
}

@main
struct ExplicitTextControllerTests {
    @MainActor static func main() {
        var passed = 0
        func check(_ name: String, _ condition: @autoclosure () -> Bool) {
            guard condition() else { fputs("FAIL: \(name)\n", stderr); exit(1) }
            passed += 1
        }
        let first = "第一句。"
        let second = "\n第二句 🛋️"
        let f = ExplicitFixture(); f.fallback()
        f.model.draft = first
        f.model.sendText(); f.reply(1)
        f.model.draft = first + second
        f.model.testReceiveFocus(1)
        check("focus refresh cannot turn a retained explicit draft into live mode", !f.model.usesLiveText && f.model.canSendText)
        f.model.openTextEditor()
        check("opening retained explicit draft never imports over the appended phrase", f.frames.count == 2 && f.model.draft == first + second)
        f.model.sendText()
        check("second Send sends only the appended phrase", f.frames.last?.fields["text"] as? String == second)
        f.reply(2)
        check("both accepted phrases stay visible and cannot resend unchanged", f.model.draft == first + second && !f.model.canSendText)
        f.model.sendText()
        check("repeated Send after ACK emits no duplicate text", f.frames.count == 3)
        f.model.draft += "\n第三句"
        f.model.sendText()
        check("third Send advances from the latest accepted snapshot", f.frames[3].fields["text"] as? String == "\n第三句")
        f.reply(3)

        let editing = ExplicitFixture(); editing.fallback()
        editing.model.draft = first; editing.model.sendText(); editing.reply(1)
        editing.model.draft = first + "未发送的草稿"
        editing.model.draft = first + "修改后的后缀"
        editing.model.sendText()
        check("editing only the unsent suffix sends its latest value", editing.frames[2].fields["text"] as? String == "修改后的后缀")
        editing.reply(2)
        editing.model.draft = "已修改首句" + "修改后的后缀"
        check("editing acknowledged prefix is retained but cannot duplicate the field", editing.model.sentTextWasEdited && !editing.model.canSendText)
        editing.model.sendText()
        check("changed acknowledged prefix is never silently submitted", editing.frames.count == 3)
        editing.model.allowManualResend(); editing.model.sendText()
        check("explicit reviewed resend may submit the whole edited draft", editing.frames[3].fields["text"] as? String == editing.model.draft)
        editing.reply(3)
        editing.model.clearDraft(); editing.model.draft = "独立新段"
        editing.model.sendText()
        check("clear begins an independent explicit segment", editing.frames[4].fields["text"] as? String == "独立新段")
        editing.reply(4)

        let pending = ExplicitFixture(); pending.fallback()
        pending.model.draft = first; pending.model.sendText()
        pending.model.draft = first + second
        check("edits while ACK is pending are retained but cannot overlap sends", pending.model.draft == first + second && !pending.model.canSendText)
        pending.reply(1)
        check("old ACK does not mark the later suffix as already sent", pending.model.canSendText && pending.model.textDelivery == .ready)
        pending.model.sendText()
        check("later suffix remains sendable exactly once after old ACK", pending.frames[2].fields["text"] as? String == second)
        pending.reply(2)

        let rejection = ExplicitFixture(); rejection.fallback()
        rejection.model.draft = first; rejection.model.sendText(); rejection.reply(1)
        rejection.model.draft += second; rejection.model.sendText()
        rejection.reply(2, ["ok": false, "error": "input_unavailable"])
        check("definite rejection retains acknowledged prefix and unsent suffix", rejection.model.canSendText && rejection.model.draft == first + second)
        rejection.model.sendText()
        check("retry after rejection still sends only the rejected suffix", rejection.frames[3].fields["text"] as? String == second)
        rejection.reply(3, ["uncertain": true])
        rejection.model.draft += "再加一句"
        check("uncertain suffix is never retried by later dictation", rejection.model.textDelivery == .uncertain && !rejection.model.canSendText)
        rejection.model.sendText()
        check("uncertain Send emits no frame", rejection.frames.count == 4)
        rejection.model.restartLiveTextEditing()
        check("reread cannot bypass an uncertain explicit delivery", rejection.frames.count == 4 && rejection.model.textDelivery == .uncertain)

        let reverted = ExplicitFixture(); reverted.fallback()
        reverted.model.draft = first; reverted.model.sendText(); reverted.reply(1)
        reverted.model.draft += second; reverted.model.draft = first
        check("deleting an unsent suffix restores the accepted receipt", reverted.model.textDelivery == .sent && !reverted.model.canSendText)
        reverted.model.draft = ""
        check("deleting an acknowledged prefix needs review", reverted.model.sentTextWasEdited && !reverted.model.canSendText)

        let normalization = ExplicitFixture(); normalization.fallback()
        normalization.model.draft = "e\u{301} 🛋️"; normalization.model.sendText(); normalization.reply(1)
        normalization.model.draft = "é 🛋️x"
        check("canonical equivalence cannot change the acknowledged UTF16 boundary", normalization.model.sentTextWasEdited && !normalization.model.canSendText)
        normalization.model.draft = "e\u{301} 🛋️x"; normalization.model.sendText()
        check("emoji and combining marks keep exact suffix boundaries", normalization.frames[2].fields["text"] as? String == "x")
        normalization.reply(2)

        let opening = ExplicitFixture(); opening.model.openTextEditor()
        opening.model.draft = "语音刚增加的内容"
        opening.reply(0, ["ok": true, "liveText": ["session": UUID().uuidString, "revision": 0,
            "text": "电脑旧内容", "selectionStart": 0, "selectionLength": 0]])
        check("direct binding change during textBegin cannot be overwritten by its ACK", opening.model.liveTextPaused && opening.model.draft == "语音刚增加的内容")
        opening.model.restartLiveTextEditing()
        check("explicit reread requests a new snapshot despite the retained local draft", opening.frames.count == 2 && opening.frames[1].type == "textBegin" && opening.model.editorLoading)
        opening.reply(1, ["ok": true, "liveText": ["session": UUID().uuidString, "revision": 0,
            "text": "明确重新读取的内容", "selectionStart": 9, "selectionLength": 0]])
        check("explicit reread imports the requested new field snapshot", opening.model.liveTextReady && opening.model.draft == "明确重新读取的内容")

        let staleOpening = ExplicitFixture(); staleOpening.model.openTextEditor()
        staleOpening.model.editText("本地新增", selection: NSRange(location: 4, length: 0), marked: false)
        staleOpening.model.restartLiveTextEditing()
        check("reread can begin before a cancelled opening request replies", staleOpening.frames.count == 2 && staleOpening.model.editorLoading)
        staleOpening.reply(0, ["ok": true, "liveText": ["session": UUID().uuidString, "revision": 0,
            "text": "过期结果", "selectionStart": 4, "selectionLength": 0]])
        check("old opening ACK cannot override a pending explicit reread", staleOpening.model.editorLoading && staleOpening.model.draft == "本地新增")
        staleOpening.reply(1, ["ok": true, "liveText": ["session": UUID().uuidString, "revision": 0,
            "text": "新的结果", "selectionStart": 4, "selectionLength": 0]])
        check("only the latest explicit reread ACK may replace the draft", staleOpening.model.liveTextReady && staleOpening.model.draft == "新的结果")

        let local = ExplicitFixture()
        local.model.draft = "Typeless返回后的本地草稿"
        local.model.openTextEditor()
        check("advertised live capability cannot import over an existing local draft", !local.model.usesLiveText && local.model.canSendText && local.frames.isEmpty)

        let storeName = "com.chekusu.sofatap.tests.explicit.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: storeName)!
        defer { store.removePersistentDomain(forName: storeName) }
        let saved = ExplicitFixture(defaults: store); saved.fallback()
        saved.model.draft = first; saved.model.sendText(); saved.reply(1)
        saved.model.draft += second
        check("receipt stores prefix length and hash instead of a second plaintext copy", store.integer(forKey: "sentDraftUTF16Length") == first.utf16.count && store.string(forKey: "sentDraftDigest")?.count == 64 && store.string(forKey: "textDeliveryMarker") == "accepted-prefix")
        let recovered = ExplicitFixture(defaults: store)
        check("restart restores unsent continuation without auto-live import", recovered.model.draft == first + second && recovered.model.canSendText && !recovered.model.usesLiveText)
        recovered.model.openTextEditor(); recovered.model.sendText()
        check("restart sends only the unacknowledged suffix", recovered.frames.count == 1 && recovered.frames[0].fields["text"] as? String == second)
        recovered.reply(0)
        let fullySent = ExplicitFixture(defaults: store)
        check("restart preserves the no-resend receipt", fullySent.model.textDelivery == .sent && !fullySent.model.canSendText)
        fullySent.model.draft = "修改了已发送开头"
        let modifiedRecovery = ExplicitFixture(defaults: store)
        check("changed stored prefix becomes uncertain after restart", modifiedRecovery.model.textDelivery == .uncertain && !modifiedRecovery.model.canSendText)
        modifiedRecovery.model.clearDraft()
        check("explicit clear removes receipt hash and prefix length", store.object(forKey: "sentDraftUTF16Length") == nil && store.object(forKey: "sentDraftDigest") == nil)
        modifiedRecovery.model.draft = "待确认"; modifiedRecovery.model.sendText()
        let pendingRecovery = ExplicitFixture(defaults: store)
        check("restart during pending send never permits automatic retry", pendingRecovery.model.textDelivery == .uncertain && !pendingRecovery.model.canSendText)
        print("Explicit text delivery: \(passed) checks passed without OS input")
    }
}
