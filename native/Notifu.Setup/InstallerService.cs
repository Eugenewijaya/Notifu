using System.Diagnostics;
using System.IO.Compression;
using Microsoft.Win32;

namespace Notifu.Setup;

internal static class InstallerService
{
    public static string InstallPath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "Notifu");

    public static void Install(Action<string> progress)
    {
        progress("Menghentikan Notifu versi lama...");
        StopRunning();
        var settingsPath = Path.Combine(InstallPath, "config", "notifu.settings.json");
        var preservedSettings = File.Exists(settingsPath) ? File.ReadAllText(settingsPath) : null;
        Directory.CreateDirectory(InstallPath);

        progress("Mengekstrak aplikasi...");
        var resource = typeof(InstallerService).Assembly.GetManifestResourceNames()
            .FirstOrDefault(x => x.EndsWith("Notifu.Payload.zip", StringComparison.OrdinalIgnoreCase))
            ?? throw new InvalidOperationException("Payload installer tidak ditemukan. Jalankan scripts/build-release.ps1.");
        using (var stream = typeof(InstallerService).Assembly.GetManifestResourceStream(resource)
               ?? throw new InvalidOperationException("Payload installer tidak dapat dibaca."))
        using (var zip = new ZipArchive(stream, ZipArchiveMode.Read))
        {
            zip.ExtractToDirectory(InstallPath, true);
        }
        if (preservedSettings is not null)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(settingsPath)!);
            File.WriteAllText(settingsPath, preservedSettings);
        }

        progress("Mendaftarkan shortcut dan uninstaller...");
        var installedUninstaller = Path.Combine(InstallPath, "Notifu.Uninstall.exe");
        File.Copy(Application.ExecutablePath, installedUninstaller, true);
        CreateShortcut(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Desktop), "Notifu.lnk"),
            Path.Combine(InstallPath, "Notifu.exe"), "", InstallPath);
        CreateShortcut(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), "Notifu.lnk"),
            Path.Combine(InstallPath, "Notifu.exe"), "", InstallPath);
        CreateShortcut(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), "Notifu Settings.lnk"),
            Path.Combine(InstallPath, "Notifu.exe"), "--settings", InstallPath);

        using (var run = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run"))
            run.SetValue("Notifu", $"\"{Path.Combine(InstallPath, "Notifu.exe")}\"");

        using (var uninstall = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Uninstall\Notifu"))
        {
            uninstall.SetValue("DisplayName", "Notifu - Your Waifu Notification");
            uninstall.SetValue("DisplayVersion", "0.2.1");
            uninstall.SetValue("Publisher", "Evid Wijaya");
            uninstall.SetValue("DisplayIcon", Path.Combine(InstallPath, "Notifu.exe"));
            uninstall.SetValue("InstallLocation", InstallPath);
            uninstall.SetValue("UninstallString", $"\"{installedUninstaller}\" --uninstall");
            uninstall.SetValue("NoModify", 1, RegistryValueKind.DWord);
            uninstall.SetValue("NoRepair", 1, RegistryValueKind.DWord);
        }

        progress("Instalasi selesai.");
    }

    public static void Launch()
    {
        var executable = Path.Combine(InstallPath, "Notifu.exe");
        if (File.Exists(executable))
            Process.Start(new ProcessStartInfo(executable) { WorkingDirectory = InstallPath, UseShellExecute = true });
    }

    public static void BeginUninstall(bool silent)
    {
        var temp = Path.Combine(Path.GetTempPath(), $"Notifu.Uninstall.{Guid.NewGuid():N}.exe");
        File.Copy(Application.ExecutablePath, temp, true);
        var silentArgument = silent ? " --silent" : "";
        Process.Start(new ProcessStartInfo(temp, $"--uninstall-from-temp \"{InstallPath}\"{silentArgument}")
        {
            UseShellExecute = true,
            WorkingDirectory = Path.GetTempPath()
        });
    }

    public static void UninstallFromTemp(string installPath, bool silent)
    {
        StopRunning();
        Thread.Sleep(800);
        DeleteShortcut(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Desktop), "Notifu.lnk"));
        DeleteShortcut(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), "Notifu.lnk"));
        DeleteShortcut(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), "Notifu Settings.lnk"));
        using (var run = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run"))
            run.DeleteValue("Notifu", false);
        Registry.CurrentUser.DeleteSubKeyTree(@"Software\Microsoft\Windows\CurrentVersion\Uninstall\Notifu", false);

        if (Directory.Exists(installPath))
            Directory.Delete(installPath, true);
        if (!silent)
            MessageBox.Show("Notifu berhasil dihapus.", "Notifu Uninstaller", MessageBoxButtons.OK, MessageBoxIcon.Information);
    }

    private static void StopRunning()
    {
        var native = Path.Combine(InstallPath, "Notifu.exe");
        if (File.Exists(native))
        {
            try
            {
                using var process = Process.Start(new ProcessStartInfo(native, "--shutdown")
                {
                    UseShellExecute = false,
                    CreateNoWindow = true
                });
                process?.WaitForExit(3000);
            }
            catch { }
        }

        foreach (var process in Process.GetProcessesByName("Notifu"))
        {
            try
            {
                process.CloseMainWindow();
                if (!process.WaitForExit(1500)) process.Kill(true);
            }
            catch { }
        }
    }

    private static void CreateShortcut(string path, string target, string arguments, string workingDirectory)
    {
        var shellType = Type.GetTypeFromProgID("WScript.Shell")
            ?? throw new InvalidOperationException("Windows Script Host tidak tersedia.");
        dynamic shell = Activator.CreateInstance(shellType)!;
        dynamic shortcut = shell.CreateShortcut(path);
        shortcut.TargetPath = target;
        shortcut.Arguments = arguments;
        shortcut.WorkingDirectory = workingDirectory;
        shortcut.IconLocation = target;
        shortcut.Description = "Notifu - Your Waifu Notification";
        shortcut.Save();
    }

    private static void DeleteShortcut(string path)
    {
        if (File.Exists(path)) File.Delete(path);
    }
}
