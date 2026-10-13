using System;
using System.IO;
using System.Reflection;
using System.Text;
using System.Globalization;
using System.Threading;
using System.Windows.Forms;
using System.Management.Automation;
using System.Management.Automation.Runspaces;

internal static class PortableHost
{
    [STAThread]
    private static int Main(string[] args)
    {
        string root = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
        bool selfTest = args.Length == 1 && args[0] == "--self-test";
        try
        {
            Environment.SetEnvironmentVariable("BBO_PORTABLE_ROOT", root, EnvironmentVariableTarget.Process);
            string script;
            using (Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("BluetoothBatteryOverlay.ps1"))
            {
                if (stream == null) throw new InvalidOperationException("Embedded overlay script is missing.");
                using (var reader = new StreamReader(stream, Encoding.UTF8)) script = reader.ReadToEnd();
            }

            using (Runspace runspace = RunspaceFactory.CreateRunspace(InitialSessionState.CreateDefault()))
            {
                runspace.ApartmentState = ApartmentState.STA;
                runspace.ThreadOptions = PSThreadOptions.UseCurrentThread;
                runspace.Open();
                using (PowerShell shell = PowerShell.Create())
                {
                    shell.Runspace = runspace;
                    shell.AddScript(script).AddParameter("Portable", true);
                    if (selfTest) shell.AddParameter("SelfTest", true);
                    shell.Invoke();
                    if (shell.HadErrors) throw new InvalidOperationException(shell.Streams.Error[0].ToString());
                }
            }
            return 0;
        }
        catch (Exception error)
        {
            string log = Path.Combine(root, "BluetoothBatteryOverlay-error.log");
            try { File.WriteAllText(log, error.ToString(), Encoding.UTF8); }
            catch
            {
                log = Path.Combine(Path.GetTempPath(), "BluetoothBatteryOverlay-error.log");
                try { File.WriteAllText(log, error.ToString(), Encoding.UTF8); }
                catch { log = "(could not save error log)"; }
            }
            if (!selfTest)
            {
                bool russian = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "ru";
                string message = russian
                    ? "Не удалось запустить Bluetooth Battery Overlay.\n\nЖурнал ошибки: " + log + "\n\n" + error.Message
                    : "Bluetooth Battery Overlay could not start.\n\nError log: " + log + "\n\n" + error.Message;
                MessageBox.Show(message, "Bluetooth Battery Overlay", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            return 1;
        }
    }
}
