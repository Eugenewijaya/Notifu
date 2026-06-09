namespace Notifu.App;

internal sealed class NotifuApplicationContext : ApplicationContext
{
    private readonly AppPaths _paths;
    private readonly AppSettings _settings;
    private readonly NotificationService _notifications;
    private readonly SpeechQueue _speech;
    private readonly NotifyIcon _tray;
    private readonly System.Windows.Forms.Timer _timer;
    private readonly Dictionary<string, DateTime> _seen = new(StringComparer.Ordinal);
    private readonly EventWaitHandle _shutdownSignal;
    private readonly SynchronizationContext _uiContext;
    private RegisteredWaitHandle? _shutdownWait;
    private NotificationPopup? _popup;
    private bool _polling;
    private bool _paused;

    public NotifuApplicationContext(AppPaths paths)
    {
        _paths = paths;
        _uiContext = SynchronizationContext.Current ?? new WindowsFormsSynchronizationContext();
        _settings = AppSettings.Load(paths);
        _notifications = new NotificationService(_settings);
        _speech = new SpeechQueue(paths, _settings);
        _tray = BuildTrayIcon();
        _timer = new System.Windows.Forms.Timer { Interval = _settings.PollMilliseconds };
        _timer.Tick += async (_, _) => await PollAsync();
        _shutdownSignal = ShutdownSignal.Listen();
        _shutdownWait = ThreadPool.RegisterWaitForSingleObject(_shutdownSignal, (_, _) =>
            _uiContext.Post(_ => Exit(), null), null, Timeout.Infinite, true);

        _ = StartAsync();
    }

    private async Task StartAsync()
    {
        try
        {
            var access = await _notifications.RequestAccessAsync();
            Log($"Native runtime started. Notification access: {access}");
            if (_settings.IgnoreExistingOnStartup)
            {
                foreach (var item in await _notifications.GetAsync()) _seen[item.UniqueKey] = DateTime.UtcNow;
            }
            _timer.Start();
        }
        catch (Exception ex)
        {
            Log($"Startup failed: {ex}");
            _tray.ShowBalloonTip(5000, "Notifu perlu akses notifikasi", ex.Message, ToolTipIcon.Warning);
            _timer.Start();
        }
    }

    private NotifyIcon BuildTrayIcon()
    {
        var menu = new ContextMenuStrip();
        var status = menu.Items.Add("Notifu aktif");
        status.Enabled = false;
        menu.Items.Add("Pause / Resume", null, (_, _) => _paused = !_paused);
        menu.Items.Add("Tes popup awan", null, (_, _) => Show(NotificationItem.Test()));
        menu.Items.Add("Settings", null, (_, _) =>
        {
            using var settings = new SettingsForm(_paths);
            settings.ShowDialog();
        });
        menu.Items.Add("Buka log", null, (_, _) =>
        {
            Directory.CreateDirectory(_paths.LogsPath);
            var path = Path.Combine(_paths.LogsPath, "notifu-native.log");
            if (!File.Exists(path)) File.WriteAllText(path, "");
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("notepad.exe", $"\"{path}\"") { UseShellExecute = true });
        });
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Matikan Notifu", null, (_, _) => Exit());

        var tray = new NotifyIcon
        {
            Text = "Notifu - Your Waifu Notification",
            Visible = _settings.ShowTrayIcon,
            ContextMenuStrip = menu
        };
        if (File.Exists(_paths.IconPath)) tray.Icon = new Icon(_paths.IconPath);
        tray.DoubleClick += (_, _) =>
        {
            using var settings = new SettingsForm(_paths);
            settings.ShowDialog();
        };
        return tray;
    }

    private async Task PollAsync()
    {
        if (_polling || _paused) return;
        _polling = true;
        try
        {
            var now = DateTime.UtcNow;
            foreach (var key in _seen.Where(x => now - x.Value > TimeSpan.FromMinutes(30)).Select(x => x.Key).ToArray())
                _seen.Remove(key);

            var next = (await _notifications.GetAsync()).FirstOrDefault(x => !_seen.ContainsKey(x.UniqueKey));
            if (next is null) return;

            _seen[next.UniqueKey] = now;
            Show(next);
            _speech.Enqueue(next.Announcement(_settings.ReadMessageBody, _settings.UserName));
            Log($"Notification shown immediately: {next.AppName} / {next.Title} / priority {next.Priority}");
        }
        catch (Exception ex)
        {
            Log($"Poll failed: {ex.Message}");
        }
        finally
        {
            _polling = false;
        }
    }

    private void Show(NotificationItem item)
    {
        _popup?.Close();
        _popup = new NotificationPopup(_paths, item, _settings.PopupDurationSeconds);
        _popup.Show();
    }

    private void Log(string message)
    {
        Directory.CreateDirectory(_paths.LogsPath);
        File.AppendAllText(Path.Combine(_paths.LogsPath, "notifu-native.log"),
            $"{DateTimeOffset.Now:O} {message}{Environment.NewLine}");
    }

    private void Exit()
    {
        _timer.Stop();
        _tray.Visible = false;
        _tray.Dispose();
        _popup?.Close();
        _shutdownWait?.Unregister(null);
        _shutdownSignal.Dispose();
        ExitThread();
    }
}
