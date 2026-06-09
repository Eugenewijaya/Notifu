namespace Notifu.App;

internal sealed record NotificationItem(
    uint Id,
    string AppName,
    string AppId,
    string Title,
    string Body,
    DateTimeOffset CreatedAt,
    int Priority)
{
    public string UniqueKey => $"{AppName.Trim().ToLowerInvariant()}:{Title.Trim().ToLowerInvariant()}:{Body.Trim().ToLowerInvariant()}";

    public string Expression
    {
        get
        {
            var text = $"{Title} {Body}".ToLowerInvariant();
            if (text.Contains("urgent") || text.Contains("penting") || text.Contains("darurat") ||
                text.Contains("otp") || text.Contains("kode verifikasi"))
            {
                return "worried";
            }
            if (text.Contains('?')) return "curious";
            if (text.Contains("meeting") || text.Contains("rapat") || text.Contains("jadwal") ||
                text.Contains("deadline"))
            {
                return "focused";
            }
            return "happy";
        }
    }

    public string Announcement(bool readBody, string userName)
    {
        var sender = string.IsNullOrWhiteSpace(Title) ? AppName : Title;
        var body = readBody && !string.IsNullOrWhiteSpace(Body)
            ? Body
            : "ada notifikasi baru yang perlu kamu lihat";
        return $"{userName}, ada notifikasi dari {sender} lewat {AppName}. {body}";
    }

    public static NotificationItem Test() =>
        new(1, "WhatsApp", "WhatsApp", "Notifu Test", "Popup awan sudah muncul tanpa menunggu AI.", DateTimeOffset.Now, 100);
}
