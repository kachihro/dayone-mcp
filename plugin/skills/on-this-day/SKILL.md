---
description: Show Day One journal entries from this day (or a given date) in previous years.
argument-hint: "[date, e.g. 25-12 or 'Christmas' — default today]"
disable-model-invocation: true
allowed-tools: mcp__plugin_dayone_dayone__on_this_day, mcp__plugin_dayone_dayone__read_entry, mcp__plugin_dayone_dayone__list_journals
---

Show the user their Day One "On This Day" memories.

Date requested: $ARGUMENTS

1. Work out the day of the year. If no date was given, use today. Accept natural forms like
   "Christmas", "tomorrow", "25 Dec" or "12/25", and convert to MM-DD for the tool. If a date like
   04/05 is ambiguous, assume the user's local convention (day/month in most of the world,
   month/day in the US), and say which you used.
2. Call `on_this_day` with that `monthDay` (check 20 years back).
3. For each year with entries, newest first, give the **year and how many years ago it was**,
   and a short, warm summary of what they wrote, with a brief quote if one stands out. Use
   `read_entry` only when an entry was shortened and the detail matters.
4. Finish with a gentle one-line reflection that ties the years together, if there's a natural one.

If there are no entries for that day, say so kindly and offer to look at nearby days.
