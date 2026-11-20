---
description: Reflect on a period of your Day One journal — themes, highlights, mood and patterns.
argument-hint: "[period, e.g. 'last month', '2024', 'this week' — default last 30 days]"
disable-model-invocation: true
allowed-tools: mcp__plugin_dayone_dayone__search_entries, mcp__plugin_dayone_dayone__list_entries, mcp__plugin_dayone_dayone__read_entry, mcp__plugin_dayone_dayone__list_journals
---

Help the user reflect on their Day One journal for this period: **$ARGUMENTS**
(If no period was given, use the last 30 days.)

1. Turn the period into exact dates (YYYY-MM-DD) based on today, and say which dates you used.
2. Get the entries with `search_entries`, leaving `query` empty and setting `dateFrom`, `dateTo`,
   `sort: entryDate` and `limit: 50`. For long periods (more than about 3 months), go through it in
   chunks, such as month by month, so nothing is missed.
3. Write a thoughtful, warm reflection:
   - **Highlights**: the moments that stood out, with dates
   - **Themes**: what kept coming up (people, places, work, health, hobbies)
   - **Mood**: how they seemed to be feeling, and how it changed over the period
   - **Patterns or gentle observations**: be kind and non-judgemental, and never diagnose
   - **A question to carry forward**: one open question they might like to journal about next
4. Mention how many entries the reflection is based on. If there were very few, say so.

Keep it personal and encouraging. Quote sparingly. These are their private words.
