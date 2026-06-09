namespace Notifu.App;

static class Program
{
    [STAThread]
    static void Main(string[] args)
    {
        ApplicationConfiguration.Initialize();

        if (args.Contains("--shutdown", StringComparer.OrdinalIgnoreCase))
        {
            ShutdownSignal.Request();
            return;
        }

        using var mutex = new Mutex(true, @"Local\Notifu-Native-Notification-Assistant", out var createdNew);
        if (!createdNew && !args.Contains("--settings", StringComparer.OrdinalIgnoreCase))
        {
            return;
        }

        var paths = AppPaths.Discover();
        if (args.Contains("--settings", StringComparer.OrdinalIgnoreCase))
        {
            Application.Run(new SettingsForm(paths));
            return;
        }

        if (args.Contains("--test-popup", StringComparer.OrdinalIgnoreCase))
        {
            using var popup = new NotificationPopup(paths, NotificationItem.Test());
            Application.Run(popup);
            return;
        }

        Application.Run(new NotifuApplicationContext(paths));
    }
}
