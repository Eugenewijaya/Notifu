namespace Notifu.Setup;

internal sealed class SetupForm : Form
{
    private readonly Label _status = new()
    {
        Text = "Siap memasang Notifu.",
        AutoSize = false,
        Height = 42,
        Dock = DockStyle.Fill,
        TextAlign = ContentAlignment.MiddleLeft
    };
    private readonly Button _install;
    private readonly Button _uninstall;
    private readonly Button _launch;

    public SetupForm()
    {
        Text = "Notifu Setup";
        ClientSize = new Size(600, 380);
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        BackColor = Color.FromArgb(247, 250, 252);
        Font = new Font("Segoe UI", 10f);

        var iconPath = Path.Combine(AppContext.BaseDirectory, "notifu-app-icon.ico");
        if (File.Exists(iconPath)) Icon = new Icon(iconPath);

        var title = new Label
        {
            Text = "Notifu",
            AutoSize = true,
            Font = new Font("Segoe UI Semibold", 28f),
            ForeColor = Color.FromArgb(25, 65, 78)
        };
        var subtitle = new Label
        {
            Text = "Your Waifu Notification",
            AutoSize = true,
            Font = new Font("Segoe UI", 12f),
            ForeColor = Color.FromArgb(72, 98, 110)
        };
        var privacy = new Label
        {
            Text = "Local-first: developer tidak mengumpulkan data pribadi atau isi notifikasi.",
            AutoSize = false,
            Height = 50,
            Dock = DockStyle.Fill,
            ForeColor = Color.FromArgb(70, 84, 96)
        };
        _install = ActionButton("Install / Update", Color.FromArgb(32, 151, 134));
        _uninstall = ActionButton("Uninstall", Color.FromArgb(190, 68, 76));
        _launch = ActionButton("Jalankan Notifu", Color.FromArgb(70, 116, 184));
        _install.Click += async (_, _) => await RunInstall();
        _uninstall.Click += (_, _) => InstallerService.BeginUninstall(false);
        _launch.Click += (_, _) => InstallerService.Launch();

        var actions = new FlowLayoutPanel { Dock = DockStyle.Fill, AutoSize = true };
        actions.Controls.AddRange([_install, _launch, _uninstall]);
        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(34), RowCount = 6, ColumnCount = 1 };
        layout.Controls.Add(title, 0, 0);
        layout.Controls.Add(subtitle, 0, 1);
        layout.Controls.Add(privacy, 0, 2);
        layout.Controls.Add(actions, 0, 3);
        layout.Controls.Add(_status, 0, 4);
        Controls.Add(layout);
    }

    private static Button ActionButton(string text, Color color) => new()
    {
        Text = text,
        AutoSize = true,
        Padding = new Padding(14, 8, 14, 8),
        BackColor = color,
        ForeColor = Color.White,
        FlatStyle = FlatStyle.Flat,
        Margin = new Padding(0, 8, 10, 8)
    };

    private async Task RunInstall()
    {
        SetEnabled(false);
        try
        {
            await Task.Run(() => InstallerService.Install(text => BeginInvoke(() => _status.Text = text)));
            _status.Text = "Notifu terpasang. Klik Jalankan Notifu.";
            MessageBox.Show("Notifu berhasil dipasang untuk user Windows ini.", "Notifu Setup",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
        catch (Exception ex)
        {
            _status.Text = "Instalasi gagal.";
            MessageBox.Show(ex.Message, "Notifu Setup", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        finally
        {
            SetEnabled(true);
        }
    }

    private void SetEnabled(bool enabled)
    {
        _install.Enabled = enabled;
        _uninstall.Enabled = enabled;
        _launch.Enabled = enabled;
    }
}
