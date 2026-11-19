using System.ComponentModel;
using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;
using ModelContextProtocol;
using ModelContextProtocol.Server;

namespace DayOneMcp;

/// <summary>
/// Read-only Day One tools for AI assistants. Searches run against the local copy
/// that the Day One CLI keeps in sync with your account.
/// </summary>
[McpServerToolType]
public sealed class DayOneTools(DayOneCli cli)
{
    private const int MaxOutputChars = 120_000;
    private const int LongStringLimit = 4_000;
    // Output goes to the model as plain text, not into HTML, so keep characters like &, " and emoji
    // readable instead of \u-escaping them (which also wastes tokens).
    private static readonly JsonSerializerOptions Pretty = new()
    {
        WriteIndented = false,
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    [McpServerTool(Name = "list_journals", Title = "List Day One journals", ReadOnly = true, Idempotent = true, Destructive = false, OpenWorld = false)]
    [Description("Lists the user's Day One journals with their IDs and names. Use the IDs to filter other tools.")]
    public async Task<string> ListJournals(CancellationToken ct)
    {
        var json = await cli.RunJsonAsync(["list", "journals"], ct);
        return Shrink(json);
    }

    [McpServerTool(Name = "search_entries", Title = "Search Day One entries", ReadOnly = true, Idempotent = true, Destructive = false, OpenWorld = false)]
    [Description("""
        Searches Day One journal entries. On Windows this is keyword search, so if nothing is found
        try synonyms or related words. Leave 'query' empty to list entries matching only the filters
        (for example a date range). Dates are interpreted in the user's local time zone.
        """)]
    public async Task<string> SearchEntries(
        [Description("Words to search for. Optional; leave empty to match every entry in the filters.")] string? query = null,
        [Description("Only entries on or after this date (YYYY-MM-DD).")] string? dateFrom = null,
        [Description("Only entries on or before this date (YYYY-MM-DD).")] string? dateTo = null,
        [Description("Limit to these journal IDs (from list_journals).")] string[]? journalIds = null,
        [Description("Only entries with these tags.")] string[]? tags = null,
        [Description("Only starred (favourite) entries.")] bool starredOnly = false,
        [Description("Only entries with this kind of media: image, video, audio or pdfAttachment.")] string? media = null,
        [Description("Sort order: relevancy (default), entryDate or editDate.")] string? sort = null,
        [Description("Maximum number of entries to return (1-50, default 10).")] int limit = 10,
        CancellationToken ct = default)
    {
        var args = new List<string> { "search", "entries", "--limit", Clamp(limit, 1, 50).ToString(CultureInfo.InvariantCulture) };
        if (!string.IsNullOrWhiteSpace(query)) args.AddRange(["--query", query.Trim()]);
        if (!string.IsNullOrWhiteSpace(dateFrom)) args.AddRange(["--date-from", LocalBound(dateFrom, endOfDay: false)]);
        if (!string.IsNullOrWhiteSpace(dateTo)) args.AddRange(["--date-to", LocalBound(dateTo, endOfDay: true)]);
        foreach (var id in journalIds ?? []) args.AddRange(["--journal-id", id]);
        foreach (var tag in tags ?? []) args.AddRange(["--tag", tag]);
        if (starredOnly) args.Add("--favorite");
        if (!string.IsNullOrWhiteSpace(media)) args.AddRange(["--media", media]);
        if (!string.IsNullOrWhiteSpace(sort)) args.AddRange(["--sort", sort]);

        var json = await cli.RunJsonAsync(args, ct);
        json.Remove("effective_params"); // echo of the arguments; not useful to the model
        return Shrink(json);
    }

    [McpServerTool(Name = "on_this_day", Title = "On This Day", ReadOnly = true, Idempotent = true, Destructive = false, OpenWorld = false)]
    [Description("Finds entries written on a given day of the year (default: today) in previous years, like Day One's 'On This Day'.")]
    public async Task<string> OnThisDay(
        [Description("Day of the year as MM-DD, e.g. 11-23. Defaults to today.")] string? monthDay = null,
        [Description("How many past years to check (1-50, default 20).")] int yearsBack = 20,
        [Description("Limit to these journal IDs (from list_journals).")] string[]? journalIds = null,
        [Description("Maximum entries per year (1-20, default 5).")] int limitPerYear = 5,
        CancellationToken ct = default)
    {
        var today = DateTime.Now.Date;
        int month = today.Month, day = today.Day;
        if (!string.IsNullOrWhiteSpace(monthDay))
        {
            if (!DateTime.TryParseExact($"2000-{monthDay.Trim()}", "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var md))
                throw new McpException($"monthDay must look like MM-DD (e.g. 11-23), not '{monthDay}'.");
            (month, day) = (md.Month, md.Day);
        }

        var years = new JsonArray();
        var total = 0;
        for (var year = today.Year - 1; year >= today.Year - Clamp(yearsBack, 1, 50); year--)
        {
            if (day > DateTime.DaysInMonth(year, month)) continue; // 29 Feb in a non-leap year
            var date = new DateTime(year, month, day).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);

            var args = new List<string>
            {
                "search", "entries",
                "--date-from", LocalBound(date, endOfDay: false),
                "--date-to", LocalBound(date, endOfDay: true),
                "--sort", "entryDate",
                "--limit", Clamp(limitPerYear, 1, 20).ToString(CultureInfo.InvariantCulture),
            };
            foreach (var id in journalIds ?? []) args.AddRange(["--journal-id", id]);

            var json = await cli.RunJsonAsync(args, ct);
            if (json["items"] is JsonArray items && items.Count > 0)
            {
                total += items.Count;
                json.Remove("items");
                years.Add(new JsonObject { ["year"] = year, ["date"] = date, ["items"] = items });
            }
        }

        var result = new JsonObject
        {
            ["ok"] = true,
            ["day"] = $"{day:00}/{month:00}",
            ["count"] = total,
            ["years"] = years,
        };
        return Shrink(result);
    }

    [McpServerTool(Name = "list_entries", Title = "List entries in a journal", ReadOnly = true, Idempotent = true, Destructive = false, OpenWorld = false)]
    [Description("Lists entries in one journal, newest first by default. Use 'cursor' from a previous result to get the next page.")]
    public async Task<string> ListEntries(
        [Description("Journal ID (from list_journals).")] string journalId,
        [Description("Maximum number of entries (1-50, default 10).")] int limit = 10,
        [Description("Show oldest entries first instead of newest.")] bool oldestFirst = false,
        [Description("Sort by entryDate (default) or editDate.")] string? sortMethod = null,
        [Description("Paging cursor ('next_cursor' from the previous page).")] string? cursor = null,
        CancellationToken ct = default)
    {
        var args = new List<string>
        {
            "list", "entries",
            "--journal-id", journalId,
            "--limit", Clamp(limit, 1, 50).ToString(CultureInfo.InvariantCulture),
            "--sort", oldestFirst ? "asc" : "desc",
        };
        if (!string.IsNullOrWhiteSpace(sortMethod)) args.AddRange(["--sort-method", sortMethod]);
        if (!string.IsNullOrWhiteSpace(cursor)) args.AddRange(["--cursor", cursor]);

        return Shrink(await cli.RunJsonAsync(args, ct));
    }

    [McpServerTool(Name = "read_entry", Title = "Read a Day One entry", ReadOnly = true, Idempotent = true, Destructive = false, OpenWorld = false)]
    [Description("Reads one entry in full. Use this when a search result was shortened.")]
    public async Task<string> ReadEntry(
        [Description("Journal ID of the entry.")] string journalId,
        [Description("Entry ID.")] string entryId,
        CancellationToken ct = default)
    {
        var json = await cli.RunJsonAsync(["entry", "read", "--journal-id", journalId, "--entry-id", entryId], ct);
        return Shrink(json, shortenLongText: false);
    }

    [McpServerTool(Name = "sync_journals", Title = "Refresh from Day One", ReadOnly = false, Idempotent = true, Destructive = false, OpenWorld = true)]
    [Description("Downloads the latest entries from the user's Day One account to the local copy that searches use. Run this if recent entries are missing.")]
    public async Task<string> SyncJournals(CancellationToken ct)
    {
        var output = await cli.RunTextAsync(["sync"], TimeSpan.FromMinutes(10), ct);
        return string.IsNullOrWhiteSpace(output) ? "Sync finished." : Truncate(output.Trim(), 4_000);
    }

    /// <summary>Turns YYYY-MM-DD into an RFC 3339 bound in the user's local time zone.</summary>
    private static string LocalBound(string value, bool endOfDay)
    {
        value = value.Trim();
        if (!DateTime.TryParseExact(value, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var date))
            return value; // already RFC 3339 or epoch ms; let the CLI validate it

        var local = endOfDay ? date.AddDays(1).AddMilliseconds(-1) : date;
        var offset = TimeZoneInfo.Local.GetUtcOffset(local);
        return new DateTimeOffset(local, offset).ToString("yyyy-MM-dd'T'HH:mm:ss.fffzzz", CultureInfo.InvariantCulture);
    }

    /// <summary>Keeps responses within a size the model can comfortably read.</summary>
    private static string Shrink(JsonObject json, bool shortenLongText = true)
    {
        var text = json.ToJsonString(Pretty);
        if (text.Length <= MaxOutputChars) return text;

        if (shortenLongText)
        {
            ShortenStrings(json);
            json["note"] = "Some long entries were shortened. Use read_entry to see an entry in full.";
            text = json.ToJsonString(Pretty);
        }

        return text.Length <= MaxOutputChars
            ? text
            : text[..MaxOutputChars] + "\n…[output truncated; narrow the search or lower the limit]";
    }

    private static void ShortenStrings(JsonNode? node)
    {
        switch (node)
        {
            case JsonObject obj:
                foreach (var key in obj.Select(p => p.Key).ToList())
                {
                    if (obj[key] is JsonValue v && v.TryGetValue<string>(out var s) && s.Length > LongStringLimit)
                        obj[key] = s[..LongStringLimit] + "…";
                    else
                        ShortenStrings(obj[key]);
                }
                break;
            case JsonArray arr:
                foreach (var item in arr) ShortenStrings(item);
                break;
        }
    }

    private static int Clamp(int value, int min, int max) => Math.Min(Math.Max(value, min), max);

    private static string Truncate(string s, int max) => s.Length <= max ? s : s[..max] + "…";
}
