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
    private static readonly string[] AnnouncementTemplates =
    [
        "{user}, ada pesan dari {sender} lewat {app}. {body}",
        "{user}, notifikasi baru nih. {sender} dari {app} bilang: {body}",
        "Eh {user}, {sender} baru mengirim pesan lewat {app}. Isinya: {body}",
        "{user}, aku langsung bacakan pesan dari {sender} di {app}. {body}",
        "Pesan masuk dari {sender} lewat {app}, {user}. {body}",
        "{user}, sebentar ya, ada kabar baru dari {sender} di {app}. {body}",
        "Notifu di sini, {user}. {sender} mengirim dari {app}: {body}",
        "{user}, ada yang baru masuk di {app} dari {sender}. {body}",
        "Aku menemukan pesan baru untukmu, {user}. Dari {sender} lewat {app}: {body}",
        "{user}, dengarkan sebentar. {sender} mengirim pesan di {app}: {body}",
        "Ada notifikasi penting untuk dicek, {user}. {sender} lewat {app} berkata: {body}",
        "{user}, pesan terbaru datang dari {sender} di {app}. Aku bacakan: {body}"
    ];

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
        var index = UniqueKey.Aggregate(0, (sum, character) => sum + character) % AnnouncementTemplates.Length;
        return AnnouncementTemplates[index]
            .Replace("{user}", userName)
            .Replace("{sender}", sender)
            .Replace("{app}", AppName)
            .Replace("{body}", body);
    }

    public static NotificationItem Test() =>
        new(1, "WhatsApp", "WhatsApp", "Notifu Test",
            "Popup awan sekarang muncul di kanan atas tanpa menunggu AI. Pesan panjang akan dibungkus dan dipotong rapi agar tidak menimpa judul, karakter, atau elemen lain di layar. Notifikasi berikutnya juga menggantikan popup sebelumnya supaya tampilannya tidak bertumpuk pada posisi yang sama.",
            DateTimeOffset.Now, 100);

    public static NotificationItem SpeechTest() =>
        new(2, "WhatsApp", "WhatsApp", "Notifu Test", "Suara langsung aktif tanpa menunggu OpenAI.",
            DateTimeOffset.Now, 100);
}
