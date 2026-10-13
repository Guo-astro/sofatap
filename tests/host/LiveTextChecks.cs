using System.Text;
using System.Text.Json;
using SofaTap;

internal static class LiveTextChecks
{
    internal static void Run(Action<bool, string> check)
    {
        var editor = new Editor();
        var input = new Input();
        using var live = new LiveTextSession(editor, () => input.Available);
        var actions = new ActionSession(input, liveText: live);
        ActionMessage Message(string type) => new(Guid.NewGuid().ToString("D"), type);
        var beginAction = Message("textBegin");
        var begun = actions.Execute(beginAction);
        var first = begun.LiveText!;
        check(begun.Ok && first.Revision == 0 && first.Text == "Existing 🛋️\ntext" && first.SelectionStart == 0,
            "live begin imports only current field with native selection");
        check(!JsonSerializer.Serialize(begun).Contains("private-target"), "live ACK excludes native target identity");
        check(actions.Execute(beginAction) == begun && editor.Reads == 1, "duplicate begin does not read a new field");
        var selectAll = Message("textSync") with { Session = first.Session, Revision = 1,
            Text = first.Text, SelectionStart = 0, SelectionLength = first.Text.Length };
        var selected = actions.Execute(selectAll);
        check(selected.Ok && editor.State.SelectionLength == first.Text.Length, "select-all synchronizes selection without changing text");
        var deletedAction = Message("textSync") with { Session = first.Session, Revision = 2, Text = "", SelectionStart = 0 };
        var deleted = actions.Execute(deletedAction);
        check(deleted.Ok && editor.State.Text == "", "deleting selected entire text synchronizes empty field");
        check(actions.Execute(deletedAction) == deleted && editor.Writes == 2, "duplicate edit cannot delete twice");
        var spokenAction = Message("textSync") with { Session = first.Session, Revision = 3, Text = "看电影", SelectionStart = 3 };
        check(actions.Execute(spokenAction).Ok, "speech transcript replaces current synchronized text");
        var revisedAction = spokenAction with { Id = Guid.NewGuid().ToString("D"), Revision = 4, Text = "看电视", SelectionStart = 3 };
        check(actions.Execute(revisedAction).Ok && editor.State.Text == "看电视", "speech correction updates instead of appending");
        var wrongOrder = revisedAction with { Id = Guid.NewGuid().ToString("D"), Revision = 6, Text = "wrong" };
        check(!actions.Execute(wrongOrder).Ok && editor.Writes == 4, "out-of-order revision cannot mutate target");
        check(!actions.Execute(revisedAction with { Id = Guid.NewGuid().ToString("D"), Revision = 5 }).Ok, "revision conflict invalidates session");

        var second = actions.Execute(Message("textBegin")).LiveText!;
        editor.State = editor.State with { SelectionStart = 0 };
        var caretConflict = Message("textSync") with { Session = second.Session, Revision = 1, Text = "remote", SelectionStart = 6 };
        check(!actions.Execute(caretConflict).Ok && editor.State.Text == "看电视", "desktop caret movement blocks stale replacement");
        second = actions.Execute(Message("textBegin")).LiveText!;
        editor.State = editor.State with { Text = "desktop edit" };
        check(!actions.Execute(caretConflict with { Id = Guid.NewGuid().ToString("D"), Session = second.Session }).Ok && editor.State.Text == "desktop edit",
            "desktop text change is never overwritten");
        second = actions.Execute(Message("textBegin")).LiveText!;
        editor.State = editor.State with { Target = "another-private-target" };
        check(!actions.Execute(caretConflict with { Id = Guid.NewGuid().ToString("D"), Session = second.Session }).Ok, "focus change blocks edit");
        second = actions.Execute(Message("textBegin")).LiveText!;
        actions.Execute(Message("click") with { Button = "left" });
        check(!actions.Execute(caretConflict with { Id = Guid.NewGuid().ToString("D"), Session = second.Session }).Ok, "pointer click ends previous edit session");
        input.Available = false;
        check(!actions.Execute(Message("textBegin")).Ok, "unavailable desktop cannot expose field contents");
        input.Available = true;
        second = actions.Execute(Message("textBegin")).LiveText!;
        editor.FailAfterWrite = true;
        var uncertain = caretConflict with { Id = Guid.NewGuid().ToString("D"), Session = second.Session };
        var failure = actions.Execute(uncertain);
        var writeCount = editor.Writes;
        check(!failure.Ok && failure.Error!.StartsWith("live_text_uncertain"), "unconfirmed native write is uncertain");
        check(actions.Execute(uncertain) == failure && editor.Writes == writeCount, "uncertain write never replayed");
        check(!actions.Execute(uncertain with { Id = Guid.NewGuid().ToString("D"), Revision = 2 }).Ok, "uncertain write invalidates editing session");
        check(!new ActionSession(input).Execute(Message("textBegin")).Ok, "legacy or unsupported receivers do not inject begin as text");

        void Reject(string extra, string name)
        {
            var body = "{\"id\":\"" + Guid.NewGuid() + "\",\"type\":\"textSync\",\"session\":\"" + Guid.NewGuid() + "\"," + extra + "}";
            try { Protocol.Parse(Encoding.UTF8.GetBytes(body)); check(false, name); }
            catch (Exception error) when (error is ProtocolException or JsonException or InvalidOperationException) { check(true, name); }
        }
        Reject("\"revision\":1,\"text\":\"🛋️\",\"selectionStart\":1,\"selectionLength\":0", "live protocol rejects selection splitting surrogate");
        Reject("\"revision\":1,\"text\":\"abc\",\"selectionStart\":2,\"selectionLength\":2", "live protocol rejects overrun selection");
        Reject("\"revision\":1.5,\"text\":\"\",\"selectionStart\":0,\"selectionLength\":0", "live protocol rejects fractional revision");
        Reject("\"revision\":true,\"text\":\"\",\"selectionStart\":0,\"selectionLength\":0", "live protocol rejects boolean revision");
        Reject("\"revision\":1,\"text\":\"\\u0000\",\"selectionStart\":0,\"selectionLength\":0", "live protocol rejects NUL");
        Reject("\"revision\":1,\"text\":\"\",\"selectionStart\":0,\"selectionLength\":0,\"extra\":1", "live protocol rejects unknown fields");
        LiveTextSession.ValidateText(new string('中', 16000), 16000, 0);
        check(JsonSerializer.SerializeToUtf8Bytes(new LiveTextSnapshot(Guid.NewGuid().ToString(), 1, new string('中', 16000), 16000, 0), LiveTextWire.Options).Length < Protocol.MaximumFrameBytes,
            "maximum Chinese snapshot fits actual response encoding");
        try { LiveTextSession.ValidateText(new string((char)1, 16000), 0, 0); check(false, "escaped control frame budget"); }
        catch (InputInjectionException) { check(true, "escaped control frame rejected before native editing"); }
    }

    private sealed class Input : IInputInjector
    {
        public bool Available { get; set; } = true;
        public void Apply(ActionMessage action) { }
        public void ReleaseAll() { }
    }
    private sealed class Editor : ILiveTextEditor
    {
        public TextEditorSnapshot State = new("private-target", "Existing 🛋️\ntext", 0, 0);
        public int Reads, Writes;
        public bool FailAfterWrite;
        public TextEditorSnapshot Read() { Reads++; return State; }
        public TextEditorSnapshot Replace(TextEditorSnapshot expected, string text, int selectionStart, int selectionLength)
        {
            if (State != expected) throw new InputInjectionException("live_text_changed: Target changed.");
            Writes++;
            State = State with { Text = text, SelectionStart = selectionStart, SelectionLength = selectionLength };
            if (FailAfterWrite) throw new InputInjectionException("live_text_uncertain: Native readback failed.");
            return State;
        }
        public void Dispose() { }
    }
}
