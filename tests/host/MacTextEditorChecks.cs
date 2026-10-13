using SofaTap;

internal static class MacTextEditorChecks
{
    internal static void Run(Action<bool, string> check)
    {
        void Error(Action action, string code, string name)
        {
            try { action(); check(false, name); }
            catch (InputInjectionException error) { check(error.Message.StartsWith(code + ":", StringComparison.Ordinal), name); }
        }

        var native = new FakeMacEditor();
        using var editor = new MacTextEditor(native);
        var original = editor.Read();
        check(original.Text == "before" && original.SelectionStart == 6, "Mac live snapshot includes exact UTF-16 text and selection");
        check(Guid.TryParseExact(original.Target, "N", out _) && !original.Target.Contains("before", StringComparison.Ordinal), "Mac native identity remains opaque");
        check(editor.Read().Target == original.Target, "Mac stable AX element keeps its session identity");
        var changed = editor.Replace(original, "中文🛋️\nnext", 10, 0);
        check(changed.Text == "中文🛋️\nnext" && changed.SelectionStart == 10 && native.Writes == 2, "Mac replacement verifies exact Unicode and selection");
        editor.Replace(changed, changed.Text, 0, 2);
        check(native.Writes == 3 && native.Value.Start == 0 && native.Value.Length == 2, "Mac selection-only edit does not rewrite text");
        var selected = editor.Read();
        editor.Replace(selected, selected.Text, selected.SelectionStart, selected.SelectionLength);
        check(native.Writes == 3, "Mac unchanged snapshot does not write");

        native.Value = native.Value with { Text = "user edit", Start = 9, Length = 0 };
        Error(() => editor.Replace(selected, "overwrite", 9, 0), "live_text_conflict", "Mac concurrent user text cannot be overwritten");
        check(native.Writes == 3 && native.Value.Text == "user edit", "Mac conflict performs no mutation");
        var beforeSelection = editor.Read();
        native.Value = native.Value with { Start = 0 };
        Error(() => editor.Replace(beforeSelection, "overwrite", 9, 0), "live_text_conflict", "Mac external caret movement stops the edit");
        var beforeFocus = editor.Read();
        native.Focus = new IntPtr(2);
        Error(() => editor.Replace(beforeFocus, "overwrite", 9, 0), "live_text_changed", "Mac new focused field cannot inherit a live-text session");
        check(native.Writes == 3, "Mac focus change performs no mutation");

        var beforeTornRead = editor.Read();
        native.OnRead = count => { if (count % 2 == 0) native.Value = native.Value with { Text = "torn read" }; };
        Error(() => editor.Read(), "live_text_changed", "Mac torn text snapshot is rejected");
        native.OnRead = null;
        check(editor.Read().Target != beforeTornRead.Target, "Mac torn snapshot invalidates the old target lease");

        var beforeWriteFailure = editor.Read();
        native.FailSelectionAtWrite = native.Writes + 3;
        Error(() => editor.Replace(beforeWriteFailure, "partial", 0, 0), "live_text_uncertain", "Mac selection write failure reports uncertain after accepted text");
        check(native.Value.Text == "partial", "Mac failed update is never rolled back over possible user edits");
        native.FailSelectionAtWrite = int.MaxValue;
        var fresh = editor.Read();
        check(fresh.Target != beforeWriteFailure.Target, "Mac partial update invalidates session identity");
        native.FocusAfterText = new IntPtr(3);
        var previousWrites = native.Writes;
        Error(() => editor.Replace(fresh, "focus moved", 11, 0), "live_text_uncertain", "Mac mid-edit focus change reports uncertain");
        check(native.Writes == previousWrites + 2, "Mac focus change during replacement suppresses subsequent selection mutation");
        native.FocusAfterText = IntPtr.Zero;
        native.Value = new("ready", 5, 0);
        fresh = editor.Read();
        native.TransformText = text => text.ToUpperInvariant();
        Error(() => editor.Replace(fresh, "transformed", 11, 0), "live_text_uncertain", "Mac provider text transformation fails exact readback verification");
        native.TransformText = null;

        native.Value = new("prefix 🛋️ suffix", 0, 0);
        fresh = editor.Read();
        native.Replacements.Clear();
        editor.Replace(fresh, "prefix 🛌️ suffix", 10, 0);
        check(native.Replacements.Count == 1 && native.Replacements[0] == (7, 2, "🛌"),
            "Mac emoji correction replaces only complete surrogate pair and leaves all surrounding styled text untouched");
        fresh = editor.Read();
        native.Replacements.Clear();
        native.OnSelection = () => native.Value = native.Value with { Text = "external" };
        Error(() => editor.Replace(fresh, "prefix 🛌️ suffix!", 18, 0), "live_text_uncertain", "Mac edit during replacement selection is detected");
        check(native.Replacements.Count == 0 && native.Value.Text == "external", "Mac changed field prevents the pending text replacement");
        native.OnSelection = null;

        native.Trusted = false;
        Error(() => editor.Read(), "live_text_unsupported", "Mac missing permission never reads text");
        native.Trusted = true;
        native.Unsupported = true;
        Error(() => editor.Read(), "live_text_unsupported", "Mac unsupported or protected provider fails closed");
        native.Unsupported = false;
        native.Focus = IntPtr.Zero;
        Error(() => editor.Read(), "live_text_unsupported", "Mac missing focus is unsupported");

        foreach (var (text, start, length) in new[]
        {
            ("🛋️", 1, 0), ("🛋️", 0, 1), ("bad\ud800", 0, 0), ("bad\udc00", 0, 0),
            ("bad\0", 0, 0), ("short", -1, 0), ("short", 4, 2), (new string('x', Protocol.MaximumTextUnits + 1), 0, 0)
        })
            Error(() => MacTextEditor.Validate(text, start, length), "live_text_unsupported", "Mac invalid Unicode/range rejected before native writes");
        MacTextEditor.Validate("👩‍👩‍👧‍👦中文\n", 0, 13);
        check(true, "Mac valid UTF-16 selection preserves complex emoji and CJK");
        editor.Dispose();
        editor.Dispose();
        Error(() => editor.Read(), "live_text_unsupported", "Mac disposed editor cannot resume its old target");
        check(native.DisposeCount == 1 && native.References == 0, "Mac target references are balanced and disposal is idempotent");
    }

    private sealed class FakeMacEditor : IMacTextEditorAccess
    {
        public bool Trusted { get; set; } = true;
        internal bool Unsupported;
        internal int FailSelectionAtWrite = int.MaxValue;
        internal IntPtr Focus = new(1), FocusAfterText;
        internal MacEditorValue Value = new("before", 6, 0);
        internal Action<int>? OnRead;
        internal Action? OnSelection;
        internal Func<string, string>? TransformText;
        internal List<(int Start, int Length, string Text)> Replacements = [];
        internal int Writes, References, DisposeCount;
        private int _reads;
        public IntPtr Focused() { if (Focus != IntPtr.Zero) References++; return Focus; }
        public bool Equal(IntPtr first, IntPtr second) => first == second;
        public void Release(IntPtr element) { if (element != IntPtr.Zero) References--; }
        public MacEditorValue Read(IntPtr element)
        {
            if (Unsupported) throw MacTextEditor.Error("live_text_unsupported", "Fixture unavailable.");
            OnRead?.Invoke(++_reads);
            return Value;
        }
        public void ReplaceSelection(IntPtr element, string text)
        {
            Writes++;
            Replacements.Add((Value.Start, Value.Length, text));
            var replacement = TransformText?.Invoke(text) ?? text;
            Value = new(Value.Text.Remove(Value.Start, Value.Length).Insert(Value.Start, replacement), Value.Start + replacement.Length, 0);
            if (FocusAfterText != IntPtr.Zero) Focus = FocusAfterText;
        }
        public void SetSelection(IntPtr element, int start, int length)
        {
            Writes++;
            if (Writes >= FailSelectionAtWrite) throw new InvalidOperationException("Fixture rejected selection.");
            Value = Value with { Start = start, Length = length };
            OnSelection?.Invoke();
        }
        public void Dispose() => DisposeCount++;
    }
}
