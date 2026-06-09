namespace Notifu.Setup;

static class Program
{
    [STAThread]
    static void Main(string[] args)
    {
        ApplicationConfiguration.Initialize();

        if (args.Length >= 2 && args[0].Equals("--uninstall-from-temp", StringComparison.OrdinalIgnoreCase))
        {
            InstallerService.UninstallFromTemp(args[1], args.Contains("--silent", StringComparer.OrdinalIgnoreCase));
            return;
        }

        if (args.Contains("--install-silent", StringComparer.OrdinalIgnoreCase))
        {
            InstallerService.Install(_ => { });
            return;
        }

        if (args.Contains("--uninstall", StringComparer.OrdinalIgnoreCase))
        {
            InstallerService.BeginUninstall(false);
            return;
        }

        if (args.Contains("--uninstall-silent", StringComparer.OrdinalIgnoreCase))
        {
            InstallerService.BeginUninstall(true);
            return;
        }

        Application.Run(new SetupForm());
    }
}
