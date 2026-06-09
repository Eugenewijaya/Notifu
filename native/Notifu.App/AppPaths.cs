namespace Notifu.App;

internal sealed record AppPaths(string Root)
{
    public string SettingsPath => Path.Combine(Root, "config", "notifu.settings.json");
    public string AssetsPath => Path.Combine(Root, "assets");
    public string LogsPath => Path.Combine(Root, "logs");
    public string SpeechQueuePath => Path.Combine(LogsPath, "speech-queue");
    public string SpeechWorkerPath => Path.Combine(Root, "scripts", "process-speech-queue.ps1");
    public string IconPath => Path.Combine(AssetsPath, "notifu-app-icon.ico");

    public static AppPaths Discover()
    {
        var candidates = new[]
        {
            AppContext.BaseDirectory,
            Environment.CurrentDirectory,
            Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", ".."))
        };

        foreach (var candidate in candidates.Distinct(StringComparer.OrdinalIgnoreCase))
        {
            if (File.Exists(Path.Combine(candidate, "config", "notifu.settings.json")))
            {
                return new AppPaths(candidate);
            }
        }

        return new AppPaths(AppContext.BaseDirectory);
    }

    public string Expression(string expression)
    {
        var safe = expression is "happy" or "talking" or "curious" or "focused" or "worried" or "sleepy"
            ? expression
            : "happy";
        return Path.Combine(AssetsPath, $"notifu-expression-{safe}.png");
    }
}
