using Windows.UI.Notifications;
using Windows.UI.Notifications.Management;

namespace Notifu.App;

internal sealed class NotificationService
{
    private readonly AppSettings _settings;

    public NotificationService(AppSettings settings) => _settings = settings;

    public async Task<string> RequestAccessAsync()
    {
        var listener = UserNotificationListener.Current;
        var status = listener.GetAccessStatus();
        if (status != UserNotificationListenerAccessStatus.Allowed)
        {
            status = await listener.RequestAccessAsync();
        }
        return status.ToString();
    }

    public async Task<IReadOnlyList<NotificationItem>> GetAsync()
    {
        var raw = await UserNotificationListener.Current.GetNotificationsAsync(NotificationKinds.Toast);
        var results = new List<NotificationItem>(raw.Count);

        foreach (var item in raw)
        {
            var appName = item.AppInfo?.DisplayInfo?.DisplayName ?? "Windows";
            if (!IsTracked(appName)) continue;

            var binding = item.Notification.Visual.GetBinding(KnownNotificationBindings.ToastGeneric);
            var text = binding?.GetTextElements().Select(x => x.Text).Where(x => !string.IsNullOrWhiteSpace(x)).ToArray() ?? [];
            var title = text.ElementAtOrDefault(0) ?? "";
            var body = string.Join(" ", text.Skip(1));
            var appId = item.AppInfo?.AppUserModelId ?? "";
            results.Add(new NotificationItem(item.Id, appName, appId, title, body, item.CreationTime, Priority(appName, $"{title} {body}")));
        }

        return results.OrderByDescending(x => x.Priority).ThenBy(x => x.CreatedAt).ToArray();
    }

    private bool IsTracked(string appName)
    {
        if (_settings.BlockApps.Any(x => appName.Contains(x, StringComparison.OrdinalIgnoreCase))) return false;
        if (_settings.NotificationMode.Equals("all", StringComparison.OrdinalIgnoreCase)) return true;
        return _settings.AllowApps.Any(x => appName.Contains(x, StringComparison.OrdinalIgnoreCase));
    }

    private int Priority(string appName, string text)
    {
        var score = 10;
        if (appName.Contains("WhatsApp", StringComparison.OrdinalIgnoreCase)) score = 120;
        else if (_settings.PriorityApps.Any(x => appName.Contains(x, StringComparison.OrdinalIgnoreCase))) score = 90;

        if (text.Contains("urgent", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("penting", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("darurat", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("otp", StringComparison.OrdinalIgnoreCase))
        {
            score += 30;
        }
        return score;
    }
}
