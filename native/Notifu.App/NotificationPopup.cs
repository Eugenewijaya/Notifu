using System.Drawing.Drawing2D;

namespace Notifu.App;

internal sealed class NotificationPopup : Form
{
    private readonly AppPaths _paths;
    private readonly NotificationItem _item;
    private readonly Label _message;
    private readonly PictureBox _avatar;
    private readonly Dictionary<string, Image> _frames = new(StringComparer.OrdinalIgnoreCase);
    private readonly System.Windows.Forms.Timer _animation = new() { Interval = 16 };
    private readonly System.Windows.Forms.Timer _typing = new() { Interval = 18 };
    private readonly System.Windows.Forms.Timer _closeTimer = new();
    private string _fullMessage = "";
    private int _typed;
    private int _targetX;
    private bool _talkingFrame;

    public NotificationPopup(AppPaths paths, NotificationItem item, int durationSeconds = 10)
    {
        _paths = paths;
        _item = item;
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual;
        ShowInTaskbar = false;
        TopMost = true;
        BackColor = Color.FromArgb(248, 252, 255);
        ClientSize = new Size(500, 205);
        DoubleBuffered = true;
        Padding = new Padding(18);

        var app = new Label
        {
            AutoSize = false,
            Location = new Point(142, 22),
            Size = new Size(322, 24),
            Font = new Font("Segoe UI Semibold", 10.5f),
            ForeColor = Color.FromArgb(30, 96, 110),
            Text = item.AppName
        };
        var sender = new Label
        {
            AutoEllipsis = true,
            Location = new Point(142, 48),
            Size = new Size(322, 28),
            Font = new Font("Segoe UI Semibold", 12.5f),
            ForeColor = Color.FromArgb(31, 39, 51),
            Text = string.IsNullOrWhiteSpace(item.Title) ? "Notifikasi baru" : item.Title
        };
        _message = new Label
        {
            AutoEllipsis = true,
            Location = new Point(142, 82),
            Size = new Size(322, 92),
            Font = new Font("Segoe UI", 10.5f),
            ForeColor = Color.FromArgb(54, 64, 78),
            TextAlign = ContentAlignment.TopLeft
        };
        _avatar = new PictureBox
        {
            Location = new Point(18, 22),
            Size = new Size(108, 108),
            SizeMode = PictureBoxSizeMode.Zoom,
            BackColor = Color.Transparent
        };
        CacheFrame(item.Expression);
        CacheFrame("talking");
        SetAvatar(item.Expression);

        Controls.AddRange([app, sender, _message, _avatar]);
        _fullMessage = PrepareDisplayMessage(item.Body);
        _closeTimer.Interval = Math.Clamp(durationSeconds, 4, 30) * 1000;
        _closeTimer.Tick += (_, _) => CloseAnimated();
        _typing.Tick += (_, _) => TypeNext();
        _animation.Tick += (_, _) => SlideIn();
        Shown += (_, _) => BeginPopup();
        Paint += PaintCloud;
        FormClosed += (_, _) => DisposeImages();
    }

    protected override bool ShowWithoutActivation => true;

    private void BeginPopup()
    {
        var work = Screen.PrimaryScreen?.WorkingArea ?? Screen.GetWorkingArea(this);
        _targetX = work.Right - Width - 18;
        Location = new Point(work.Right + 10, work.Top + 18);
        Region = Region.FromHrgn(CreateRoundRectRgn(0, 0, Width, Height, 34, 34));
        _animation.Start();
        _typing.Start();
        _closeTimer.Start();
    }

    private void SlideIn()
    {
        Left = Math.Max(_targetX, Left - Math.Max(24, (Left - _targetX) / 4));
        if (Left <= _targetX) _animation.Stop();
    }

    private void TypeNext()
    {
        _typed = Math.Min(_fullMessage.Length, _typed + 2);
        _message.Text = _fullMessage[.._typed];
        if (_typed % 8 == 0)
        {
            _talkingFrame = !_talkingFrame;
            SetAvatar(_talkingFrame ? "talking" : _item.Expression);
        }
        if (_typed >= _fullMessage.Length)
        {
            _typing.Stop();
            SetAvatar(_item.Expression);
        }
    }

    private void CloseAnimated()
    {
        _closeTimer.Stop();
        _typing.Stop();
        Close();
    }

    private void CacheFrame(string expression)
    {
        if (_frames.ContainsKey(expression)) return;
        var path = _paths.Expression(expression);
        if (!File.Exists(path)) return;
        using var source = Image.FromFile(path);
        _frames[expression] = new Bitmap(source, _avatar.Size);
    }

    private void SetAvatar(string expression)
    {
        if (_frames.TryGetValue(expression, out var image)) _avatar.Image = image;
    }

    private void DisposeImages()
    {
        _avatar.Image = null;
        foreach (var image in _frames.Values) image.Dispose();
        _frames.Clear();
    }

    private static string PrepareDisplayMessage(string message)
    {
        var normalized = string.IsNullOrWhiteSpace(message)
            ? "Ada notifikasi baru yang perlu kamu lihat."
            : string.Join(" ", message.Split(default(string[]), StringSplitOptions.RemoveEmptyEntries));
        return normalized.Length <= 320 ? normalized : $"{normalized[..317]}...";
    }

    private void PaintCloud(object? sender, PaintEventArgs e)
    {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        using var border = new Pen(Color.FromArgb(91, 204, 190), 2f);
        using var accent = new SolidBrush(Color.FromArgb(226, 249, 245));
        e.Graphics.FillEllipse(accent, 8, 8, 120, 45);
        e.Graphics.DrawRoundedRectangle(border, new RectangleF(2, 2, Width - 5, Height - 5), 30);
        using var tail = new GraphicsPath();
        tail.AddPolygon([new Point(106, Height - 6), new Point(132, Height - 6), new Point(118, Height + 12)]);
        using var tailBrush = new SolidBrush(BackColor);
        e.Graphics.FillPath(tailBrush, tail);
    }

    [System.Runtime.InteropServices.DllImport("gdi32.dll")]
    private static extern IntPtr CreateRoundRectRgn(int left, int top, int right, int bottom, int width, int height);
}

internal static class GraphicsExtensions
{
    public static void DrawRoundedRectangle(this Graphics graphics, Pen pen, RectangleF bounds, float radius)
    {
        using var path = new GraphicsPath();
        var diameter = radius * 2;
        path.AddArc(bounds.Left, bounds.Top, diameter, diameter, 180, 90);
        path.AddArc(bounds.Right - diameter, bounds.Top, diameter, diameter, 270, 90);
        path.AddArc(bounds.Right - diameter, bounds.Bottom - diameter, diameter, diameter, 0, 90);
        path.AddArc(bounds.Left, bounds.Bottom - diameter, diameter, diameter, 90, 90);
        path.CloseFigure();
        graphics.DrawPath(pen, path);
    }
}
