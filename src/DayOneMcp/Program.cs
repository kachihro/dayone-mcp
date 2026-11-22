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
        o.ServerInfo = new()
        {
            Name = "dayone",
            Title = "Day One Journal by kachihro",
            Version = version,
            Description = "Search and read your Day One journal. Read-only. Made by kachihro (www.kachihro.com).",
            WebsiteUrl = "https://github.com/kachihro/dayone-mcp",
            Icons = LoadIcon(),
        };
    })
    .WithStdioServerTransport()
    .WithTools<DayOneTools>();

await builder.Build().RunAsync();
return 0;

// The app icon, embedded in the executable and sent as a data URI so it works offline.
static List<ModelContextProtocol.Protocol.Icon>? LoadIcon()
{
    using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("DayOneMcp.icon.png");
    if (stream is null) return null;
    using var ms = new MemoryStream();
    stream.CopyTo(ms);
    return
    [
        new()
        {
            Source = "data:image/png;base64," + Convert.ToBase64String(ms.ToArray()),
            MimeType = "image/png",
            Sizes = ["128x128"],
        },
    ];
}
