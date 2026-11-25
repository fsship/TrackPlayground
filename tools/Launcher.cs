using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

internal static class Launcher
{
    [STAThread]
    private static void Main()
    {
        try
        {
            string root = AppDomain.CurrentDomain.BaseDirectory;
            string engine = Path.Combine(root, "runtime", "Godot.exe");
            if (!File.Exists(engine)) throw new FileNotFoundException("缺少 runtime/Godot.exe，请保持程序目录完整。", engine);
            string roaming = Path.Combine(root, ".runtime", "Roaming");
            string local = Path.Combine(root, ".runtime", "Local");
            Directory.CreateDirectory(roaming);
            Directory.CreateDirectory(local);
            var start = new ProcessStartInfo(engine);
            start.WorkingDirectory = root;
            start.Arguments = "--path \"" + root.TrimEnd('\\') + "\" --log-file \"" + Path.Combine(root, "runtime.log") + "\"";
            start.UseShellExecute = false;
            start.CreateNoWindow = true;
            start.EnvironmentVariables["APPDATA"] = roaming;
            start.EnvironmentVariables["LOCALAPPDATA"] = local;
			if (!File.Exists(Path.Combine(root, ".godot", "global_script_class_cache.cfg")))
			{
				string gameArguments = start.Arguments;
				start.Arguments = gameArguments + " --headless --editor --import --quit";
				var import = Process.Start(start);
				import.WaitForExit();
				if (import.ExitCode != 0) throw new Exception("首次导入失败，请查看 runtime.log。");
				start.Arguments = gameArguments;
			}
            var process = Process.Start(start);
            process.WaitForExit();
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, "轨道工坊启动失败", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }
}
