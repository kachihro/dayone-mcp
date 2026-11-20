---
name: journal
description: How to search and read the user's Day One journal well. Use whenever the user asks about their journal, diary, Day One entries, or what they wrote, did, felt or remembered on a date or about a topic (for example "what did I write about Japan?", "how was I feeling last March?", "when did I last see Sam?").
---

# Working with the user's Day One journal

The `dayone` MCP server (from this plugin) gives read-only access to the user's Day One journal
through the official Day One CLI. Tools:

| Tool | Use it for |
|---|---|
| `search_entries` | Keyword search with optional `dateFrom`/`dateTo` (YYYY-MM-DD), `journalIds`, `tags`, `starredOnly`, `media`, `sort`, `limit` (max 50) |
| `on_this_day` | Entries from a day of the year (`monthDay` as MM-DD, default today) in past years |
| `list_journals` | Journal names and IDs |
| `list_entries` | Browse one journal, newest first (use `cursor` to page) |
| `read_entry` | One entry in full, when a search result was shortened |
| `sync_journals` | Download the latest entries from Day One |

## Searching well

- **Search is keyword-based** on Windows and Intel Macs, not meaning-based. A query only matches
  entries containing those words. For a topic, run a few searches with synonyms and related words
  (for example "holiday", "vacation", "trip", "beach", plus the place name). Combine and de-duplicate
  the results.
- **Leave `query` empty** to get every entry in a date range. This is the best way to answer
  "what happened in May 2024?" or "how was last week?".
- **Dates are in the user's local time zone.** Turn "last summer" or "last month" into exact
  `dateFrom`/`dateTo` values based on today's date, and remember seasons differ by hemisphere.
  If the hemisphere matters and you don't know it, ask.
- Sort by `entryDate` when the order of events matters, and keep `relevancy` for topic searches.
- If recent entries seem to be missing, call `sync_journals`, then search again.

## Answering

- Be warm and personal. This is someone's private journal, not a database.
- Always give the **date** of each entry you draw on, so the user can find it in Day One.
- Prefer short quotes and summaries over pasting whole entries.
- Don't invent details. If nothing matches, say so and suggest other words or dates to try.
- The tools are read-only. If the user asks to add or change entries, explain that this plugin
  can't do that yet, and they can do it in the Day One app.

## If something's wrong

- The tools aren't available, or no journals come back: suggest running `/dayone:setup`.
- An error mentions signing in: the user needs to run `dayone setup` in their own terminal.
  It asks for their password, so they should do it themselves, not through you.
- Encrypted journals return nothing: they need `dayone auth key-set` with their Day One
  encryption key.
