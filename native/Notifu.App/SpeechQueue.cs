using System.Diagnostics;

namespace Notifu.App;

internal sealed class SpeechQueue
{
    private readonly AppPaths _paths;
    private readonly AppSettings _settings;
    private Process? _worker;

    public SpeechQueue(AppPaths paths, AppSettings settings)
    {
        _paths = paths;
        _settings = settings;
    }

    public void Enqueue(string text)
    {
        if (!_settings.VoiceEnabled || string.IsNullOrWhiteSpace(text) || !File.Exists(_paths.SpeechWorkerPath))
        {
            return;
        }

        Directory.CreateDirectory(_paths.SpeechQueuePath);
        var name = $"{DateTime.UtcNow:yyyyMMddHHmmssfff}-{Guid.NewGuid():N}.txt";
        File.WriteAllText(Path.Combine(_paths.SpeechQueuePath, name), text);
        StartWorker();
    }

    private void StartWorker()
    {
        if (_worker is { HasExited: false }) return;

        var powerShell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32",
            "WindowsPowerShell", "v1.0", "powershell.exe");
        _worker = Process.Start(new ProcessStartInfo
        {
            FileName = powerShell,
            Arguments = $"-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"{_paths.SpeechWorkerPath}\" -SettingsPath \"{_paths.SettingsPath}\"",
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden
        });
    }
}
