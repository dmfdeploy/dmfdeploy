---
name: safari-applescript-browser-checks
description: Drive the operator's signed-in Safari on macOS with AppleScript (osascript) to run read-only browser checks, such as console page moves, deep-link reloads and Grafana dashboards. Covers consent, the targeting requirements for a dedicated window, the macOS settings, how to pass JavaScript, single-page app navigation proof, lazy-loaded panels, possible failure messages, and what never to click or read. Use when a check needs the operator's real browser session and no test browser is connected.
type: durable-pattern
scope: agent-workflow
owner: operator
review_by: '2027-05-27'
source_ref: https://github.com/dmfdeploy/dmfdeploy/issues/1020
---

# Safari browser checks through AppleScript

Use this skill when a check has to run in the operator's real browser, with their sign-ins and cookies, and no test browser (Playwright, a Chrome extension) is connected. On macOS, `osascript` can open a Safari window, compare its URL and title with expected values, and run JavaScript in the page. That's enough for read-only checks: page moves, a deep link through a reload, and dashboards that load with data.

It isn't a test framework. JavaScript clicks find elements by text or attributes, and they break when the page changes. Keep it to a handful of checks and record the expected values and the results.

## 0. Rules (read first)

1. **Ask the operator first.** It's their browser and their signed-in sessions. Get a plain yes before the first `osascript` call, and say you'll work in a separate window.
2. **Read-only by default.** Never click anything that changes state (deploy, switch, delete, save, approve, sign out) unless the operator asks for that exact click. Hand state-changing clicks to the operator and check the result yourself, for example on the cluster.
3. **Leave the operator's tabs alone.** Work only in a Safari window you created, and meet the targeting requirements in section 2 before every operation. Never fall back to the front window or the current tab.
4. **Read only the minimum non-sensitive fields needed for the check.** Don't read, print or record credentials, tokens, cookies, storage, form values, private identifiers, or sensitive page or API content. Use narrowly scoped boolean checks or sanitized counts. Stop if you can't inspect the page safely.
5. **If a sign-in or passkey prompt appears, stop** and let the operator complete it.
6. **Public text stays generic.** Evidence that leaves the machine names no hosts, env ids or user names.

## 1. One-time setup on the Mac

Settings and exact prompts vary by macOS and Safari version. The messages below are possible symptoms; each can have other causes. The operator changes each setting; you can't.

| Needed for | Setting | A possible symptom without it |
|---|---|---|
| Any `tell application "Safari"` | The first call shows a macOS prompt asking whether the terminal app may control Safari. The operator allows it. Later changes: **System Settings > Privacy & Security > Automation**, terminal app, **Safari** on. | The call hangs, then `AppleEvent timed out. (-1712)`. The prompt can be hidden behind other windows. |
| `do JavaScript` | **Safari > Settings > Advanced > Show features for web developers**, then **Develop > Allow JavaScript from Apple Events**. | `You must enable 'Allow JavaScript from Apple Events' … (8)` |
| Screenshots with `screencapture` | **System Settings > Privacy & Security > Screen Recording**, terminal app on. | `could not create image from window` or `… from display` |

Screenshots are optional. A sanitized reading through JavaScript is good evidence on its own. Don't ask for Screen Recording unless a picture is needed.

When the checks are done, close your window and tell the operator they can turn **Allow JavaScript from Apple Events** off again.

## 2. Building the commands

This skill gives no ready-to-run window or request scripts: Safari doesn't give tabs a stable id, and a script that guesses its target can act on the operator's tab. Write your own commands for the task, and hold them to these requirements.

**Timeouts.** Bound every `osascript` call with an outer process timeout (GNU coreutils `timeout`, often installed as `gtimeout` on macOS; stop if neither exists) and with AppleScript's `with timeout of … seconds` for Apple Event replies. A pending permission prompt otherwise hangs the call.

**Targeting.** Capture the identity of the window created by the creation operation from the returned object or another verified association; never infer ownership from whichever window is frontmost afterward. Retain and verify the identity of the original task tab as well as the window. Before every JavaScript call, navigation, reload or close, verify that both still exist and remain the intended targets. If either identity can't be established or has changed, stop without operating on any tab or window. Don't fall back to the front window or to tab 1. On the Safari version at hand, first establish a working window-creation method and verify that the returned window and original task tab can both be identified across the required operations. If creation fails or either identity can't be established, stop without operating on any tab or window and hand the check to the operator. Don't claim the procedure is validated until the page move, reload and verified close have all been exercised with consent.

A trial on Safari 27.0.1 (2026-11-27) used a before-and-after window ID comparison, then tagged the sole tab with a random `window.name` and checked the window ID, visibility, tab count and tag before later operations. It completed a page move, reload and close, and rejected a wrong tag. These checks do not prove that the tab tagged initially is the one created for the task, or that an unrelated window cannot be mistaken for the created window if windows change during creation. A page can also change its own `window.name`. Treat this as session evidence only. It isn't a verified targeting method. If you cannot independently establish the created window and original tab identities before the first JavaScript call and verify them before every later operation, stop and hand the check to the operator.

In that trial, `make new window` failed, filtering windows by `document` wasn't supported, and `before` turned out to be a reserved word in AppleScript.

**JavaScript.** Pass the script to `osascript` as an argument (`osascript - "$js"` with an `on run argv` handler). Spliced into AppleScript source, it would need extra quoting. Return strings, or wrap small objects in `JSON.stringify(...)`.

**Reload.** Setting a tab's URL to its own URL performs a full reload.

**Closing.** Safari can keep a closed window's id with no tabs, so `exists` can stay true after a close. Check that the window is visible and has tabs before treating it as open.

**Requests from the page.** `do JavaScript` returns before an asynchronous `fetch` finishes, and requests from the page carry the operator's session. Use only endpoints and fields the operator approved; a GET request alone doesn't prove an endpoint has no side effects. Set a fresh `pending` result before each request, check `r.ok`, and store `done` with only the approved non-sensitive fields, or `error`. Poll only until a fixed wall-clock deadline. Check each call's exit status and parse its result. Accept only `pending`, `done` and `error`: continue for `pending`, report the approved result for `done`, and report the check as unproven for `error`, a failed call, malformed or missing output, an unexpected state, or deadline expiry. Bound each call by the time remaining. Don't treat an empty or unexpected response as success.

## 3. Patterns

### Prove a client-side page move (single-page apps)

Before the run, write down the expected path, title and heading. Set a marker on `window`, click the link, then compare the path, title and heading with those values inside the page. Return only booleans. If the marker survives, the app moved without a full page load. After a reload, the marker must be gone.

```javascript
// 1. set the marker
window.__mark = Date.now(); "marked"
// 2. click the visible link
(() => { const a = [...document.querySelectorAll('a[href="/facilities"]')].find(a => a.offsetParent !== null); if (!a) return 'no visible link'; a.click(); return 'ok'; })()
// 3. after 3 to 4 seconds, compare with the expected values you chose before the run
(() => { const want = { path: '/facilities', title: 'EXPECTED TITLE', heading: 'EXPECTED HEADING' }; const h = document.querySelector('h1'); return JSON.stringify({ pathOk: location.pathname === want.path, titleOk: document.title === want.title, headingOk: !!h && h.textContent.trim() === want.heading, sameDoc: !!window.__mark }); })()
```

- Click only a **visible** link (`offsetParent !== null`). Menus and collapsed rails can hold hidden copies of the same link.
- Leave 3 to 4 seconds between clicks. A click sent while the app is still moving can be dropped. After every click, check that the path equals the expected value, and retry once if it doesn't.
- A heading alone can mislead. Check for the expected heading, known non-sensitive page-specific markers and known error markers. Report only booleans or sanitized counts.

### Deep link through a reload

Open the deep link by a click, reload the tab, wait about 6 seconds, then check, as booleans: the URL equals the expected value, marker gone, the expected heading and the expected page markers.

### Grafana dashboards

Grafana markup and lazy loading vary by version. Inspect the rendered panel container and identify its title, visible `No data` state and error indicator; validate the selector against the current page. Scroll the relevant container incrementally and verify that all expected panels rendered before counting. Record absolute start and end times and resolved variable values when safe to read; a dashboard definition alone doesn't prove the resolved value. Investigate an empty panel before calling it a defect: for example, query the panel's expression in Prometheus, because panels filtered to `> 0` are empty when nothing happened.

## 4. Possible failure messages

| Message | Possible cause | What to try |
|---|---|---|
| `AppleEvent timed out. (-1712)` | A pending permission prompt, an unresponsive app or another Apple Event failure. | Ask the operator to look for the prompt, or to check Safari under Automation for the terminal app. |
| `You must enable 'Allow JavaScript from Apple Events' … (8)` | The Develop setting is off. | Section 1, second row. |
| `could not create image from …` | Missing permission or another capture failure. | Skip the screenshot, or ask for the permission. |
| Your target check fails | The operator or Safari closed or changed your window or tab. | Stop. Ask before you open a new window. |
| The click returns `ok` but the path doesn't change | Hidden duplicate link, or a click sent while the page was still moving. | Click the visible link, wait, check the path against the expected value, retry once. |

## 5. Recording

Write down the expected values you chose, the boolean results and any sanitized counts (path, title and heading checks, absolute time in UTC), in the evidence file, and say how the check was run: "Safari driven by AppleScript, with the operator's yes". Say what wasn't covered, such as no screenshot. A reading from the operator's browser proves what that session saw, at that time.
