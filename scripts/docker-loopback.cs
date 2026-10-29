// Lanzador local para la CLI: modifica únicamente puertos de este proyecto.
// No registra argumentos ni entorno; Docker recibe stdin/stdout/stderr originales.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;

public static class DockerLoopback {
    static string Quote(string value) {
        if (value.Length > 0 && !Regex.IsMatch(value, "[\\s\"]")) return value;
        var output = new StringBuilder("\"");
        int slashes = 0;
        foreach (char c in value) {
            if (c == '\\') { slashes++; continue; }
            if (c == '"') { output.Append('\\', slashes * 2 + 1); output.Append(c); }
            else { output.Append('\\', slashes); output.Append(c); }
            slashes = 0;
        }
        output.Append('\\', slashes * 2);
        return output.Append('"').ToString();
    }
    static string LocalPort(string value) {
        if (Regex.IsMatch(value, @"^\d+(?:-\d+)?:\d+(?:-\d+)?(?:/(?:tcp|udp))?$")) return "127.0.0.1:" + value;
        if (Regex.IsMatch(value, @"^127\.0\.0\.1:\d+(?:-\d+)?:\d+(?:-\d+)?(?:/(?:tcp|udp))?$")) return value;
        throw new InvalidOperationException("Puerto de proyecto sin dirección loopback válida.");
    }
    public static int Main(string[] args) {
        try {
            bool create = args.Length > 0 && (args[0] == "create" || args[0] == "run");
            bool owned = false;
            for (int i = 0; i + 1 < args.Length; i++) {
                if (args[i] == "--name" && args[i+1].StartsWith("supabase_", StringComparison.Ordinal) && args[i+1].EndsWith("_micatalogo-test", StringComparison.Ordinal)) owned = true;
            }
            if (create && owned) {
                for (int i = 1; i < args.Length; i++) {
                    if (args[i] == "-P" || args[i] == "--publish-all") throw new InvalidOperationException("Publicación automática no permitida.");
                    if (args[i] == "-p" || args[i] == "--publish") {
                        if (++i >= args.Length) throw new InvalidOperationException("Falta el puerto.");
                        args[i] = LocalPort(args[i]);
                    } else if (args[i].StartsWith("--publish=", StringComparison.Ordinal)) args[i] = "--publish=" + LocalPort(args[i].Substring(10));
                }
            }
            var quoted = new List<string>();
            foreach (string arg in args) quoted.Add(Quote(arg));
            var binary = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Docker", "Docker", "resources", "bin", "docker.exe");
            var start = new ProcessStartInfo(binary, String.Join(" ", quoted.ToArray()));
            start.UseShellExecute = false;
            start.CreateNoWindow = true;
            start.RedirectStandardInput = true;
            start.RedirectStandardOutput = true;
            start.RedirectStandardError = true;
            using (var process = Process.Start(start)) {
                var input = Console.OpenStandardInput().CopyToAsync(process.StandardInput.BaseStream);
                input.ContinueWith(task => { try { process.StandardInput.Close(); } catch {} });
                var output = process.StandardOutput.BaseStream.CopyToAsync(Console.OpenStandardOutput());
                var error = process.StandardError.BaseStream.CopyToAsync(Console.OpenStandardError());
                process.WaitForExit();
                Task.WaitAll(output, error);
                return process.ExitCode;
            }
        } catch {
            Console.Error.WriteLine("No se pudo ejecutar Docker con los puertos locales del proyecto.");
            return 125;
        }
    }
}
