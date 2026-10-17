namespace SofaTap.Desktop;

// A directory transaction keeps the install path (and shortcuts) unchanged.
// The previous tree is retained even after success, providing a manual recovery
// path if the process or machine is stopped between filesystem operations.
internal sealed class UpdateTransaction(string installation, string stage, string backup, string failed, Action<string, string>? move = null)
{
    private readonly Action<string, string> _move = move ?? Directory.Move;
    private bool _originalMoved;
    private bool _replacementMoved;
    internal bool Started => _originalMoved;
    internal void Install()
    {
        if (Directory.Exists(backup) || File.Exists(backup) || Directory.Exists(failed) || File.Exists(failed))
            throw new IOException("更新恢复目录已存在。");
        _move(installation, backup); _originalMoved = true;
        _move(stage, installation); _replacementMoved = true;
    }
    internal void Rollback()
    {
        if (!_originalMoved) return;
        if (_replacementMoved) { _move(installation, failed); _replacementMoved = false; }
        _move(backup, installation); _originalMoved = false;
    }
}
