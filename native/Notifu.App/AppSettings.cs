using System.Text.Json;
using System.Text.Json.Nodes;

namespace Notifu.App;

internal sealed class AppSettings
{
    public int PollMilliseconds { get; init; } = 1000;
    public int PopupDurationSeconds { get; init; } = 10;
    public bool IgnoreExistingOnStartup { get; init; } = true;
    public bool VoiceEnabled { get; init; } = true;
    public bool AiEnabled { get; init; }
    public bool ReadMessageBody { get; init; } = true;
    public bool ShowTrayIcon { get; init; } = true;
    public bool StartWithWindows { get; init; } = true;
    public string UserName { get; init; } = "Evid";
    public string NotificationMode { get; init; } = "all";
    public IReadOnlyList<string> AllowApps { get; init; } = [];
    public IReadOnlyList<string> BlockApps { get; init; } = ["Notifu"];
    public IReadOnlyList<string> PriorityApps { get; init; } =
        ["WhatsApp", "Chrome", "Microsoft Edge", "Firefox", "Brave", "Opera"];

    public static AppSettings Load(AppPaths paths)
    {
        try
        {
            var root = JsonNode.Parse(File.ReadAllText(paths.SettingsPath))?.AsObject();
            return new AppSettings
            {
                PollMilliseconds = Math.Max(500, ReadInt(root, "listener", "pollMilliseconds",
                    ReadInt(root, "listener", "pollSeconds", 1) * 1000)),
                PopupDurationSeconds = Math.Clamp(ReadInt(root, "ui", "popupDurationSeconds", 10), 4, 30),
                IgnoreExistingOnStartup = ReadBool(root, "listener", "ignoreExistingOnStartup", true),
                VoiceEnabled = ReadBool(root, "voice", "enabled", true),
                AiEnabled = ReadBool(root, "ai", "enabled", false),
                ReadMessageBody = ReadBool(root, "privacy", "readMessageBody", true),
                ShowTrayIcon = ReadBool(root, "ui", "showTrayIcon", true),
                StartWithWindows = ReadBool(root, "runtime", "startWithWindows", true),
                UserName = ReadString(root, "assistant", "userName", "Evid"),
                NotificationMode = ReadString(root, "notifications", "mode", "all"),
                AllowApps = ReadStrings(root, "notifications", "allowAppNameContains"),
                BlockApps = ReadStrings(root, "notifications", "blockAppNameContains", ["Notifu"]),
                PriorityApps = ReadStrings(root, "notifications", "priorityAppNameContains",
                    ["WhatsApp", "Chrome", "Microsoft Edge", "Firefox", "Brave", "Opera"])
            };
        }
        catch
        {
            return new AppSettings();
        }
    }

    public static void Save(AppPaths paths, AppSettings settings)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(paths.SettingsPath)!);
        var root = File.Exists(paths.SettingsPath)
            ? JsonNode.Parse(File.ReadAllText(paths.SettingsPath))?.AsObject() ?? new JsonObject()
            : new JsonObject();

        Set(root, "listener", "pollMilliseconds", settings.PollMilliseconds);
        Set(root, "listener", "pollSeconds", Math.Max(1, settings.PollMilliseconds / 1000));
        Set(root, "ui", "popupDurationSeconds", settings.PopupDurationSeconds);
        Set(root, "ui", "enableDesktopPet", false);
        Set(root, "voice", "enabled", settings.VoiceEnabled);
        Set(root, "ai", "enabled", false);
        Set(root, "privacy", "readMessageBody", settings.ReadMessageBody);
        Set(root, "runtime", "startWithWindows", settings.StartWithWindows);
        Set(root, "notifications", "priorityAppNameContains",
            new JsonArray(settings.PriorityApps.Select(value => JsonValue.Create(value)).ToArray()));
        File.WriteAllText(paths.SettingsPath, root.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
    }

    private static JsonObject Section(JsonObject root, string section)
    {
        if (root[section] is JsonObject value)
        {
            return value;
        }
        value = new JsonObject();
        root[section] = value;
        return value;
    }

    private static void Set(JsonObject root, string section, string key, JsonNode? value) =>
        Section(root, section)[key] = value;

    private static int ReadInt(JsonObject? root, string section, string key, int fallback) =>
        root?[section]?[key]?.GetValue<int>() ?? fallback;

    private static bool ReadBool(JsonObject? root, string section, string key, bool fallback) =>
        root?[section]?[key]?.GetValue<bool>() ?? fallback;

    private static string ReadString(JsonObject? root, string section, string key, string fallback) =>
        root?[section]?[key]?.GetValue<string>() ?? fallback;

    private static IReadOnlyList<string> ReadStrings(
        JsonObject? root, string section, string key, IReadOnlyList<string>? fallback = null)
    {
        if (root?[section]?[key] is not JsonArray values)
        {
            return fallback ?? [];
        }
        return values.Select(x => x?.GetValue<string>() ?? "").Where(x => x.Length > 0).ToArray();
    }
}
