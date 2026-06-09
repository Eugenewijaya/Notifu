using Microsoft.Win32;

namespace Notifu.App;

internal sealed class SettingsForm : Form
{
    private readonly AppPaths _paths;
    private readonly CheckBox _voice = new() { Text = "Aktifkan suara notifikasi", AutoSize = true };
    private readonly CheckBox _privacy = new() { Text = "Bacakan isi pesan", AutoSize = true };
    private readonly CheckBox _startup = new() { Text = "Jalankan Notifu saat login Windows", AutoSize = true };
    private readonly NumericUpDown _poll = new() { Minimum = 500, Maximum = 10000, Increment = 250, Width = 110 };
    private readonly NumericUpDown _duration = new() { Minimum = 4, Maximum = 30, Width = 110 };
    private readonly TextBox _priority = new() { Multiline = true, Height = 72, Dock = DockStyle.Fill };

    public SettingsForm(AppPaths paths)
    {
        _paths = paths;
        Text = "Notifu Settings";
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(620, 510);
        MinimumSize = new Size(620, 510);
        BackColor = Color.FromArgb(247, 250, 252);
        Font = new Font("Segoe UI", 10f);
        if (File.Exists(paths.IconPath)) Icon = new Icon(paths.IconPath);

        var title = new Label
        {
            Text = "Notifu Settings",
            Font = new Font("Segoe UI Semibold", 20f),
            AutoSize = true,
            ForeColor = Color.FromArgb(28, 48, 64)
        };
        var subtitle = new Label
        {
            Text = "Runtime native hemat RAM. Popup tampil dahulu, AI dan voice menyusul.",
            AutoSize = true,
            ForeColor = Color.FromArgb(86, 101, 115)
        };
        var layout = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            Padding = new Padding(28),
            ColumnCount = 2,
            RowCount = 10
        };
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 58));
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 42));
        layout.Controls.Add(title, 0, 0);
        layout.SetColumnSpan(title, 2);
        layout.Controls.Add(subtitle, 0, 1);
        layout.SetColumnSpan(subtitle, 2);
        layout.Controls.Add(_voice, 0, 2);
        layout.SetColumnSpan(_voice, 2);
        layout.Controls.Add(_privacy, 0, 3);
        layout.SetColumnSpan(_privacy, 2);
        layout.Controls.Add(_startup, 0, 4);
        layout.SetColumnSpan(_startup, 2);
        layout.Controls.Add(new Label { Text = "Polling notifikasi (ms)", AutoSize = true }, 0, 5);
        layout.Controls.Add(_poll, 1, 5);
        layout.Controls.Add(new Label { Text = "Durasi popup (detik)", AutoSize = true }, 0, 6);
        layout.Controls.Add(_duration, 1, 6);
        layout.Controls.Add(new Label { Text = "Aplikasi prioritas, satu per baris", AutoSize = true }, 0, 7);
        layout.Controls.Add(_priority, 1, 7);

        var buttons = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.RightToLeft, AutoSize = true };
        var save = Button("Simpan", Color.FromArgb(35, 150, 135));
        var test = Button("Tes Popup", Color.FromArgb(75, 119, 190));
        var exit = Button("Matikan Notifu", Color.FromArgb(194, 67, 76));
        save.Click += (_, _) => Save();
        test.Click += (_, _) => new NotificationPopup(_paths, NotificationItem.Test()).Show();
        exit.Click += (_, _) =>
        {
            ShutdownSignal.Request();
            Close();
        };
        buttons.Controls.AddRange([save, test, exit]);
        layout.Controls.Add(buttons, 0, 9);
        layout.SetColumnSpan(buttons, 2);
        Controls.Add(layout);
        LoadValues();
    }

    private static Button Button(string text, Color color) => new()
    {
        Text = text,
        AutoSize = true,
        Padding = new Padding(14, 7, 14, 7),
        BackColor = color,
        ForeColor = Color.White,
        FlatStyle = FlatStyle.Flat
    };

    private void LoadValues()
    {
        var settings = AppSettings.Load(_paths);
        _voice.Checked = settings.VoiceEnabled;
        _privacy.Checked = settings.ReadMessageBody;
        _startup.Checked = settings.StartWithWindows;
        _poll.Value = settings.PollMilliseconds;
        _duration.Value = settings.PopupDurationSeconds;
        _priority.Text = string.Join(Environment.NewLine, settings.PriorityApps);
    }

    private void Save()
    {
        var settings = AppSettings.Load(_paths);
        var updated = new AppSettings
        {
            PollMilliseconds = (int)_poll.Value,
            PopupDurationSeconds = (int)_duration.Value,
            IgnoreExistingOnStartup = settings.IgnoreExistingOnStartup,
            VoiceEnabled = _voice.Checked,
            AiEnabled = false,
            ReadMessageBody = _privacy.Checked,
            ShowTrayIcon = settings.ShowTrayIcon,
            StartWithWindows = _startup.Checked,
            UserName = settings.UserName,
            NotificationMode = settings.NotificationMode,
            AllowApps = settings.AllowApps,
            BlockApps = settings.BlockApps,
            PriorityApps = _priority.Lines.Select(x => x.Trim()).Where(x => x.Length > 0).ToArray()
        };
        AppSettings.Save(_paths, updated);
        SetStartup(updated.StartWithWindows);
        MessageBox.Show("Settings tersimpan. Restart Notifu untuk menerapkan semuanya.", "Notifu",
            MessageBoxButtons.OK, MessageBoxIcon.Information);
    }

    private static void SetStartup(bool enabled)
    {
        using var key = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run");
        if (enabled) key.SetValue("Notifu", $"\"{Application.ExecutablePath}\"");
        else key.DeleteValue("Notifu", false);
    }
}
