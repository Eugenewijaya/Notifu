namespace Notifu.App;

internal static class ShutdownSignal
{
    private const string Name = @"Local\Notifu-Native-Shutdown";

    public static EventWaitHandle Listen() => new(false, EventResetMode.AutoReset, Name);

    public static void Request()
    {
        try
        {
            using var signal = EventWaitHandle.OpenExisting(Name);
            signal.Set();
        }
        catch
        {
            // No native Notifu instance is running.
        }
    }
}
