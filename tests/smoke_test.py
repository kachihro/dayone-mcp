#!/usr/bin/env python3
"""
End-to-end smoke test: starts the MCP server over stdio and calls every read-only tool
against the real Day One CLI (signed out, so it has no journals).

    python3 tests/smoke_test.py <path-to-DayOneMcp> <path-to-dayone-binary>
"""
import json
import os
import subprocess
import sys

server, dayone = sys.argv[1], sys.argv[2]
env = dict(os.environ, DAYONE_CLI_PATH=dayone, DO_NOT_TRACK="1", TZ="Australia/Sydney")
proc = subprocess.Popen([server], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        stderr=subprocess.DEVNULL, text=True, env=env)
next_id = 0
failures = 0


def rpc(method, params=None, notify=False):
    global next_id
    msg = {"jsonrpc": "2.0", "method": method}
    if params is not None:
        msg["params"] = params
    if not notify:
        next_id += 1
        msg["id"] = next_id
    proc.stdin.write(json.dumps(msg) + "\n")
    proc.stdin.flush()
    return None if notify else json.loads(proc.stdout.readline())


def check(name, condition, detail=""):
    global failures
    print(("PASS " if condition else "FAIL ") + name + (f"  ({detail})" if detail and not condition else ""))
    failures += 0 if condition else 1


def call(tool, args):
    result = rpc("tools/call", {"name": tool, "arguments": args})["result"]
    return result.get("isError", False), result["content"][0]["text"]


init = rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                          "clientInfo": {"name": "smoke-test", "version": "1"}})
check("initialize", init["result"]["serverInfo"]["name"] == "dayone")
rpc("notifications/initialized", notify=True)

tools = {t["name"]: t for t in rpc("tools/list")["result"]["tools"]}
expected = {"list_journals", "search_entries", "on_this_day", "list_entries", "read_entry", "sync_journals"}
check("tools/list has all tools", set(tools) == expected, str(sorted(tools)))
check("every tool is read-only", all(tools[t]["annotations"]["readOnlyHint"] for t in expected))
check("no tool is destructive", not any(tools[t]["annotations"].get("destructiveHint") for t in expected))

err, text = call("list_journals", {})
check("list_journals", not err and json.loads(text)["ok"], text)

err, text = call("search_entries", {"query": 'beach & "sun" 🏖️', "dateFrom": "2025-01-01",
                                    "dateTo": "2025-01-31", "tags": ["holiday"], "limit": 5})
body = json.loads(text) if not err else {}
check("search_entries passes special characters through", body.get("query") == 'beach & "sun" 🏖️', text)
check("search_entries hides effective_params", "effective_params" not in body)

err, text = call("on_this_day", {"monthDay": "02-29", "yearsBack": 5})
check("on_this_day handles 29 Feb", not err and json.loads(text)["day"] == "29/02", text)

err, text = call("on_this_day", {"monthDay": "13-45"})
check("on_this_day rejects bad dates", err and "MM-DD" in text, text)

err, text = call("read_entry", {"journalId": "x", "entryId": "missing"})
check("read_entry reports CLI errors with a hint", err and "dayone sync" in text, text)

err, text = call("list_entries", {"journalId": "x", "limit": 3})
check("list_entries", not err and json.loads(text)["ok"], text)

proc.stdin.close()
proc.wait(timeout=15)
print(f"\n{'All tests passed' if failures == 0 else f'{failures} test(s) failed'}")
sys.exit(1 if failures else 0)
