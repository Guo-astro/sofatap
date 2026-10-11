namespace SofaTap;

// Only this small state crosses the wire. Native accessibility identities stay local.
public sealed record TextFocusMetadata(string State, int Revision);

public sealed class TextFocusTracker
{
    private TextFocusSnapshot _previous = new(TextFocusKind.Unknown);
    private int _revision;

    public TextFocusMetadata Update(TextFocusSnapshot snapshot, bool inputAvailable)
    {
        if (!inputAvailable) snapshot = new(TextFocusKind.Unknown);
        if (snapshot != _previous)
        {
            _previous = snapshot;
            _revision = _revision == int.MaxValue ? 1 : _revision + 1;
        }
        var state = snapshot.Kind switch
        {
            TextFocusKind.Editable => "editable",
            TextFocusKind.Other => "other",
            TextFocusKind.Protected => "protected",
            _ => "unknown"
        };
        return new(state, _revision);
    }
}
