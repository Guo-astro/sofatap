import Foundation

@main
struct DictationTranscriptTests {
    static func main() {
        var passed = 0
        func check(_ name: String, _ condition: @autoclosure () -> Bool) {
            guard condition() else { fputs("FAIL: \(name)\n", stderr); exit(1) }
            passed += 1
        }

        let base = "Sofatap Windows 实测\n中文・日本語・emoji 🛋️\n原草稿仍然保留"
        let spoken = "今天晚上我想坐在沙发上看电影"
        var recognition = DictationTranscript()
        var draft = base
        func receive(_ candidate: String?) {
            if recognition.receive(candidate),
               let replacement = DictationTranscript.draft(base: base, transcript: recognition.text,
                                                           ownsDraft: true, sessionIsActive: true) {
                draft = replacement
            }
        }
        receive("今天晚上")
        receive(spoken)
        check("partial speech appends to the existing multi-line draft", draft == base + "\n" + spoken)

        // Reproduce stopping a recognizer which returns a present but empty final
        // result after a usable partial result. The whole utterance used to vanish.
        receive("")
        check("empty final result preserves the full utterance", draft == base + "\n" + spoken)
        check("empty final result preserves the recognizer's retained text", recognition.text == spoken)
        receive(nil)
        check("error without a result preserves the draft", draft == base + "\n" + spoken)
        receive(" \n\t")
        check("whitespace-only terminal result cannot clear speech", recognition.text == spoken)

        receive("今晚看电影。")
        check("a shorter nonempty final correction replaces the partial result", draft == base + "\n今晚看电影。")
        check("an unchanged callback does not publish again", !recognition.receive("今晚看电影。"))
        receive("Hello 👋 日本語")
        check("Unicode correction is retained exactly", recognition.text == "Hello 👋 日本語")

        recognition = DictationTranscript()
        check("a new recording resets the retained transcript", recognition.text.isEmpty)
        check("a silent recording has no draft replacement", DictationTranscript.draft(base: base, transcript: recognition.text,
                                                                                      ownsDraft: true, sessionIsActive: true) == nil)
        receive("新的录音")
        check("new recording does not retain an older utterance", recognition.text == "新的录音")

        check("empty base needs no leading newline", DictationTranscript.draft(base: "", transcript: spoken,
                                                                              ownsDraft: true, sessionIsActive: true) == spoken)
        check("existing trailing whitespace needs no extra separator", DictationTranscript.draft(base: "前缀\n", transcript: spoken,
                                                                                                ownsDraft: true, sessionIsActive: true) == "前缀\n" + spoken)
        check("nonempty recognition keeps its formatting", DictationTranscript.draft(base: "", transcript: "你好。\n第二句。",
                                                                                    ownsDraft: true, sessionIsActive: true) == "你好。\n第二句。")

        // @Published can replay the previous result to a newly created SwiftUI
        // subscription after the user has already edited or cleared the draft.
        let preservedEdits = ["", "用户修改后的草稿"].allSatisfy { edited in
            var current = edited
            if let replay = DictationTranscript.draft(base: base, transcript: spoken,
                                                      ownsDraft: false, sessionIsActive: false) { current = replay }
            return current == edited
        }
        check("idle subscription replay preserves edits and an explicit clear", preservedEdits)

        // toggleDictation claims the draft before its asynchronous start task
        // resets the transcript. The prior session is still idle in that gap.
        var nextDraft = "第二次录音前的草稿"
        if let replay = DictationTranscript.draft(base: nextDraft, transcript: spoken,
                                                  ownsDraft: true, sessionIsActive: false) { nextDraft = replay }
        check("claiming the next recording does not append the prior idle result", nextDraft == "第二次录音前的草稿")
        print("Dictation transcript: \(passed) checks passed without microphone access or OS input")
    }
}
