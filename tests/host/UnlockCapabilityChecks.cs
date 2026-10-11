using System.Text;
using System.Text.Json;
using SofaTap;

static class UnlockCapabilityChecks
{
    public static void Run(Action<bool, string> check)
    {
        var pin = new string('a', 64);
        // Synthetic values only. Never load a real installed login profile.
        var fields = new Dictionary<string, object>
        {
            ["receiverFingerprint"] = pin, ["version"] = 1, ["port"] = 53320,
            ["fingerprint"] = new string('b', 64), ["token"] = new string('A', 43),
            ["deviceId"] = "3a33231b-c402-4dc2-a4ea-e28f6a8f7862", ["accountName"] = "test-user",
            ["accountSid"] = "S-1-5-21-100-200-300-1001", ["provider"] = "windows-local-password"
        };
        byte[] Body() => JsonSerializer.SerializeToUtf8Bytes(fields);
        var capability = UnlockCapabilityStore.Parse(Body(), pin);
        check(capability is { Version: 1, Port: 53320 }, "explicit login capability parses");
        check(!capability!.ToString().Contains(new string('A', 43)), "diagnostic formatting redacts login token");
        check(UnlockCapabilityStore.Parse(Body(), new string('c', 64)) is null, "receiver identity rotation invalidates login enrollment");
        foreach (var pair in new Dictionary<string, object>
        {
            ["version"] = 2, ["port"] = 80, ["fingerprint"] = new string('G', 64),
            ["token"] = new string('A', 42) + "B", ["deviceId"] = Guid.Empty.ToString("D"),
            ["accountName"] = "domain\\user", ["accountSid"] = "S-1-5-21-100-200-300-9999999999",
            ["provider"] = "windows-hello-pin"
        })
        {
            var previous = fields[pair.Key]; fields[pair.Key] = pair.Value;
            check(UnlockCapabilityStore.Parse(Body(), pin) is null, "reject invalid login capability " + pair.Key);
            fields[pair.Key] = previous;
        }
        fields["provider"] = "windows-microsoft-password";
        check(UnlockCapabilityStore.Parse(Body(), pin)?.Provider == "windows-microsoft-password", "explicit personal Microsoft password provider parses");
        fields["accountName"] = "email@example.invalid";
        check(UnlockCapabilityStore.Parse(Body(), pin) is null, "capability uses fixed profile alias rather than a network-selected online identity");
        fields["accountName"] = "test-user";
        fields["provider"] = "windows-entra-password";
        check(UnlockCapabilityStore.Parse(Body(), pin) is null, "unsupported identity provider rejected");
        fields["provider"] = "windows-local-password";
        fields["host"] = "other-device.invalid";
        check(UnlockCapabilityStore.Parse(Body(), pin) is null, "capability cannot redirect to another host");
        fields.Remove("host");
        var valid = Encoding.UTF8.GetString(Body());
        check(UnlockCapabilityStore.Parse(Encoding.UTF8.GetBytes(valid[..^1] + ",\"port\":53320}"), pin) is null,
            "duplicate enrollment field rejected");
        fields.Remove("accountSid");
        check(UnlockCapabilityStore.Parse(Body(), pin) is null, "missing fixed account rejected");
        check(UnlockCapabilityStore.Parse(Encoding.UTF8.GetBytes(new string(' ', 8193)), pin) is null, "capability size bounded");
        check(UnlockCapabilityStore.Read("unused-test-path", pin, true, true, "ready") is null, "dry-run never advertises login");
        check(UnlockCapabilityStore.Read("unused-test-path", pin, false, false, "ready") is null, "other OS never advertises Windows login");
        check(UnlockCapabilityStore.Read("unused-test-path", pin, true, false, "desktop_locked") is null, "locked receiver never starts enrollment");
    }
}
