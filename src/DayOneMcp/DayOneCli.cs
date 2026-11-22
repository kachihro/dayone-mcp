using System.Diagnostics;
using System.Text;
using System.Text.Json.Nodes;
using Microsoft.Extensions.Logging;
using ModelContextProtocol;

namespace DayOneMcp;

/// <summary>
/// Runs the official Day One CLI (@dayone/cli) and returns its JSON output.
/// Arguments are passed through ProcessStartInfo.ArgumentList, so search text is never
/// interpreted by a shell.
/// </summary>
public sealed class DayOneCli(ILogger<DayOneCli> logger)
{
    private static readonly TimeSpan Timeout = TimeSpan.FromSeconds(120);
    private readonly Lazy<string> _exePath = new(ResolveExecutable);

    /// <summary>Runs a command whose output may not be JSON (e.g. sync). Throws on a non-zero exit.</summary>
    public async Task<string> RunTextAsync(IReadOnlyList<string> args, TimeSpan timeout, CancellationToken ct)
    {
        var (exitCode, stdout, stderr) = await RunAsync(args, ct, timeout);
        if (exitCode != 0)
        {
            var message = FirstNonEmpty(stderr, stdout) ?? "no output";
            throw new McpException(
                $"Day One CLI failed (exit {exitCode}): {Truncate(message.Trim(), 2000)}" + Hint(message));
        }
        return stdout;
    }

    public async Task<JsonObject> RunJsonAsync(IReadOnlyList<string> args, CancellationToken ct)
    {
        var (exitCode, stdout, stderr) = await RunAsync(args, ct);

        JsonObject? json = null;
        try { json = JsonNode.Parse(stdout) as JsonObject; } catch { /* not JSON, handled below */ }

        if (exitCode != 0 || json is null || json["ok"]?.GetValue<bool>() == false)
        {
            var message = FirstNonEmpty(stderr, json?["error"]?.ToJsonString(), stdout) ?? "no output";
            throw new McpException(
                $"Day One CLI failed (exit {exitCode}): {Truncate(message.Trim(), 2000)}" + Hint(message));
        }

        return json;
    }

    private async Task<(int ExitCode, string Stdout, string Stderr)> RunAsync(
        IReadOnlyList<string> args, CancellationToken ct, TimeSpan? timeout = null)
    {
        var limit = timeout ?? Timeout;
        var psi = new ProcessStartInfo(_exePath.Value)
        {
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8,
        };
        foreach (var a in args) psi.ArgumentList.Add(a);

        // Keep the CLI quiet and non-interactive: no telemetry, no update banner.
        psi.Environment["DO_NOT_TRACK"] = "1";
        psi.Environment["DAYONE_TELEMETRY"] = "0";
        psi.Environment["NO_UPDATE_NOTIFIER"] = "1";

        logger.LogDebug("Running dayone {Command}", string.Join(' ', args.Take(2)));

        using var process = new Process { StartInfo = psi };
        try
        {
            process.Start();
        }
        catch (Exception ex)
        {
            throw new McpException(
                $"Could not start the Day One CLI at '{_exePath.Value}': {ex.Message}. " +
                "Install it with 'npm install -g @dayone/cli', or set DAYONE_CLI_PATH to dayone.exe.");
        }

        // Never wait on an interactive prompt.
        process.StandardInput.Close();

        var stdoutTask = process.StandardOutput.ReadToEndAsync(ct);
        var stderrTask = process.StandardError.ReadToEndAsync(ct);

        using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeoutCts.CancelAfter(limit);
        try
        {
            await process.WaitForExitAsync(timeoutCts.Token);
        }
        catch (OperationCanceledException)
        {
            try { process.Kill(entireProcessTree: true); } catch { /* already gone */ }
            if (ct.IsCancellationRequested) throw;
            throw new McpException($"Day One CLI timed out after {limit.TotalSeconds:0} seconds.");
        }

        return (process.ExitCode, await stdoutTask, await stderrTask);
    }

    /// <summary>
    /// Finds the native Day One binary. Calling it directly (rather than the npm "dayone.cmd"
    /// shim) avoids cmd.exe argument parsing, so characters like &amp; or " in a search are safe.
    /// </summary>
    private static string ResolveExecutable()
    {
        // 1. Explicit setting. Ignore an unfilled "${user_config...}" placeholder from a Claude Desktop extension.
        var fromEnv = Environment.GetEnvironmentVariable("DAYONE_CLI_PATH")?.Trim().Trim('"');
        if (!string.IsNullOrWhiteSpace(fromEnv) && !fromEnv.Contains("${"))
        {
            if (File.Exists(fromEnv)) return fromEnv;
            throw new McpException($"DAYONE_CLI_PATH is set to '{fromEnv}', but that file does not exist.");
        }

        // 2. Path saved by the installer: next to this executable, or in the installer's folder (for copies
        //    that run from elsewhere, such as the Claude Desktop extension or the Claude Code plugin).
        foreach (var savedFile in SavedPathFiles())
        {
            if (!File.Exists(savedFile)) continue;
            var saved = File.ReadAllText(savedFile).Trim().Trim('"');
            if (File.Exists(saved)) return saved;
        }

        return FindCandidates().FirstOrDefault(File.Exists)
            ?? throw new McpException(
                "Can't find the Day One CLI. Please re-run the Day One MCP installer: https://github.com/kachihro/dayone-mcp");
    }

    /// <summary>
    /// Node.js installs managed by nvm keep a separate set of global npm packages for each Node version,
    /// so the Day One CLI may live under a version that isn't the active one. Its native binary doesn't
    /// need Node to run, so any copy works. Yields npm prefix folders, newest Node version first.
    /// </summary>
    private static IEnumerable<string> NvmPrefixes(string home)
    {
        var roots = new List<string>();
        if (OperatingSystem.IsWindows())
        {
            roots.Add(Environment.GetEnvironmentVariable("NVM_HOME") ?? "");
            roots.Add(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "nvm"));
            roots.Add(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "nvm"));
            roots.Add(@"C:\nvm4w");
        }
        else
        {
            var nvmDir = Environment.GetEnvironmentVariable("NVM_DIR");
            roots.Add(Path.Combine(string.IsNullOrEmpty(nvmDir) ? Path.Combine(home, ".nvm") : nvmDir, "versions", "node"));
        }

        foreach (var root in roots.Where(r => !string.IsNullOrWhiteSpace(r)).Distinct(StringComparer.OrdinalIgnoreCase))
        {
            string[] versions;
            try { versions = Directory.Exists(root) ? Directory.GetDirectories(root, "v*") : []; }
            catch { continue; }
            foreach (var dir in versions.OrderByDescending(d => Version.TryParse(Path.GetFileName(d).TrimStart('v'), out var v) ? v : new Version(0, 0)))
                yield return OperatingSystem.IsWindows() ? dir : Path.Combine(dir, "lib");
        }
    }

    private static IEnumerable<string> SavedPathFiles()
    {
        yield return Path.Combine(AppContext.BaseDirectory, "dayone-cli-path.txt");
        yield return OperatingSystem.IsWindows()
            ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "dayone-mcp", "dayone-cli-path.txt")
            : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".local", "share", "dayone-mcp", "dayone-cli-path.txt");
    }

    private static IEnumerable<string> FindCandidates()
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var pathDirs = (Environment.GetEnvironmentVariable("PATH") ?? "")
            .Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries)
            .Select(d => d.Trim('"'))
            .ToList();

        if (OperatingSystem.IsWindows())
        {
            // npm puts a "dayone.cmd" shim in its global folder and the real binary in
            // <prefix>\node_modules\@dayone\cli\node_modules\@dayone\cli-win32-x64\dayone.exe (or hoisted).
            // Check npm's default prefix plus every PATH folder (covers nvm-windows, volta, custom prefixes).
            var prefixes = new List<string>
            {
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "npm"),
            };
            prefixes.AddRange(pathDirs);
            prefixes.AddRange(NvmPrefixes(home));

            foreach (var prefix in prefixes)
            {
                var scope = Path.Combine(prefix, "node_modules", "@dayone");
                yield return Path.Combine(scope, "cli", "node_modules", "@dayone", "cli-win32-x64", "dayone.exe");
                yield return Path.Combine(scope, "cli-win32-x64", "dayone.exe");
            }

            // A standalone binary from GitHub Releases, wherever it is on PATH.
            foreach (var dir in pathDirs)
            {
                yield return Path.Combine(dir, "dayone.exe");
                yield return Path.Combine(dir, "dayone-win32-x64.exe");
            }
        }
        else
        {
            // GUI apps (e.g. Claude Desktop on macOS) often start with a minimal PATH, so also check
            // the usual npm / Homebrew / user bin folders. On these platforms the npm "dayone" is a
            // Node launcher, which needs 'node' on PATH; set DAYONE_CLI_PATH if it can't find it.
            var platform = OperatingSystem.IsMacOS() ? "darwin" : "linux";
            var arch = System.Runtime.InteropServices.RuntimeInformation.OSArchitecture == System.Runtime.InteropServices.Architecture.Arm64 ? "arm64" : "x64";
            foreach (var prefix in NvmPrefixes(home))
            {
                var scope = Path.Combine(prefix, "node_modules", "@dayone", "cli", "node_modules", "@dayone");
                yield return Path.Combine(scope, $"cli-{platform}-{arch}", "dayone");
                yield return Path.Combine(scope, $"cli-{platform}-{arch}-no-embeddings", "dayone");
            }

            var extra = new[]
            {
                "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin",
                Path.Combine(home, ".local", "bin"),
                Path.Combine(home, ".npm-global", "bin"),
                Path.Combine(home, ".volta", "bin"),
            };
            foreach (var dir in pathDirs.Concat(extra).Distinct())
                yield return Path.Combine(dir, "dayone");
        }
    }

    private static string Hint(string message)
    {
        var m = message.ToLowerInvariant();
        if (m.Contains("sync")) return " Hint: run 'dayone sync' in a terminal, or call the sync_journals tool.";
        if (m.Contains("auth") || m.Contains("login") || m.Contains("token"))
            return " Hint: sign in by running 'dayone setup' in a terminal.";
        if (m.Contains("key") && m.Contains("encrypt"))
            return " Hint: add your encryption key with 'dayone auth key-set'.";
        return "";
    }

    private static string? FirstNonEmpty(params string?[] values) =>
        values.FirstOrDefault(v => !string.IsNullOrWhiteSpace(v));

    private static string Truncate(string s, int max) => s.Length <= max ? s : s[..max] + "…";
}
