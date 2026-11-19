using System.Reflection;
using DayOneMcp;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;

var version = Assembly.GetExecutingAssembly()
    .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion.Split('+')[0] ?? "0.0.0";

// --version : print the version and exit.
if (args.Contains("--version"))
{
    Console.WriteLine($"dayone-mcp {version}");
    return 0;
}

// --check : confirm the Day One CLI can be found and has journals, then exit (used by the installers).
if (args.Contains("--check"))
{
    try
    {
        var cli = new DayOneCli(NullLogger<DayOneCli>.Instance);
        var journals = await cli.RunJsonAsync(["list", "journals"], CancellationToken.None);
        var count = journals["count"]?.GetValue<int>() ?? 0;
        Console.WriteLine(count > 0
            ? $"OK: Day One CLI found, {count} journal(s) available."
            : "WARNING: Day One CLI found, but no journals yet. Run 'dayone setup' then 'dayone sync'.");
        return count > 0 ? 0 : 2;
    }
    catch (Exception ex)
    {
        Console.WriteLine($"ERROR: {ex.Message}");
        return 1;
    }
}

var builder = Host.CreateApplicationBuilder(args);

// MCP over stdio: stdout is reserved for protocol messages, so every log line goes to stderr.
builder.Logging.AddConsole(o => o.LogToStandardErrorThreshold = LogLevel.Trace);
builder.Logging.SetMinimumLevel(LogLevel.Warning);

builder.Services.AddSingleton<DayOneCli>();

builder.Services
    .AddMcpServer(o =>
    {
        o.ServerInfo = new() { Name = "dayone", Version = version };
    })
    .WithStdioServerTransport()
    .WithTools<DayOneTools>();

await builder.Build().RunAsync();
return 0;
