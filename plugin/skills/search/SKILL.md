---
description: Search your Day One journal for a topic, person, place or feeling.
argument-hint: "<what to look for, e.g. 'trips to Japan' or 'Mum's birthday'>"
disable-model-invocation: true
allowed-tools: mcp__plugin_dayone_dayone__search_entries, mcp__plugin_dayone_dayone__read_entry, mcp__plugin_dayone_dayone__list_journals
---

Search the user's Day One journal for: **$ARGUMENTS**

If nothing was given to search for, ask what they'd like to find.

1. Search is keyword-based, so run `search_entries` several times: the user's own words first,
   then 3 to 6 synonyms, related words, names or places. Use date filters if the request
   mentions a time ("last year", "in 2023").
2. Merge the results and drop duplicates (the same entry ID).
3. Reply with:
   - a one-paragraph answer to what they were really asking
   - the most relevant entries in date order, each with its **date**, the journal name if there
     are several journals, and a one-line summary or short quote
   - the words you searched for, so they can ask you to try others
4. If there are lots of matches, show the 10 most relevant and offer to show more or narrow it down.
5. If nothing matches, suggest other words or date ranges to try.
