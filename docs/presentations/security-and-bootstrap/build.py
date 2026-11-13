#!/usr/bin/env python3
"""Build deck.html from deck.md. Python 3 standard library only.

Usage: python3 build.py [deck.md] [deck.html]

deck.md format:
  - Slides are separated by a line that contains only "---".
  - "Part: text" sets the small label above the title.
  - "# text" is the slide title. "## text" is an optional subtitle.
  - "- [tag] text" is a bullet. Tags: do, see, holds, why, miss (row labels).
  - "![alt](path)" places a diagram.
  - A block of lines that start with "|" is a table.
  - "Notes:" starts the speaker notes. Notes are not shown in the PDF.
"""
import html
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "illustrations"))
import icons  # Material Icons paths (Apache-2.0), see illustrations/icon-credits.txt

ICON_SVG = {
    ":lock-open:": ('<svg class="ico" viewBox="0 0 24 24" role="img" aria-label="open padlock: vault open">'
                    '<title>Vault open</title><path d="%s" fill="#1e7a34"/></svg>' % icons.LOCK_OPEN),
    ":lock-closed:": ('<svg class="ico" viewBox="0 0 24 24" role="img" aria-label="closed padlock: vault closed">'
                      '<title>Vault closed</title><path d="%s" fill="#c92a2a"/></svg>' % icons.LOCK_CLOSED),
}

TAGS = {
    "do": "You do",
    "see": "You see",
    "holds": "System holds",
    "why": "Why",
    "miss": "If you miss it",
}

CSS = """
@page { size: 1600px 900px; margin: 0; }
* { box-sizing: border-box; }
html, body { margin: 0; padding: 0; }
body { font-family: Helvetica, Arial, sans-serif; color: #1b1b1b; background: #fff; }
.slide { width: 1600px; height: 900px; padding: 56px 80px 40px 80px; position: relative;
  page-break-after: always; break-after: page; overflow: hidden; display: flex; flex-direction: column; }
.slide:last-child { page-break-after: auto; break-after: auto; }
.part { font-size: 22px; letter-spacing: 0.04em; text-transform: uppercase; color: #1971c2; margin-bottom: 8px; }
h1 { font-size: 50px; line-height: 1.12; margin: 0 0 10px 0; font-weight: 700; }
h2 { font-size: 28px; font-weight: 400; color: #495057; margin: 0 0 14px 0; }
.diagram { text-align: center; margin: 4px 0 8px 0; flex: 0 0 auto; }
.diagram img { width: 1250px; height: auto; max-height: 400px; object-fit: contain; }
ul { list-style: none; padding: 0; margin: 8px 0 0 0; }
li { font-size: 27px; line-height: 1.32; margin: 0 0 12px 0; padding-left: 0; }
.nodiagram li { font-size: 32px; margin-bottom: 20px; }
.pill { display: inline-block; font-size: 18px; font-weight: 700; padding: 2px 11px; border-radius: 14px;
  margin-right: 12px; vertical-align: 3px; border: 2px solid; white-space: nowrap; }
.pill { min-width: 168px; text-align: center; }
li.tagged { padding-left: 180px; text-indent: -180px; }
.pill { text-indent: 0; }
.pill.do { background: #d0ebff; border-color: #1971c2; color: #0b4a8a; }
.pill.see { background: #d3f9d8; border-color: #2b8a3e; color: #1b5e28; }
.pill.holds { background: #fff3bf; border-color: #e67700; color: #7a4100; }
.pill.why { background: #f1f3f5; border-color: #868e96; color: #343a40; }
.pill.miss { background: #ffe3e3; border-color: #c92a2a; color: #8a1c1c; }
table { border-collapse: collapse; width: 100%; font-size: 23px; margin-top: 6px; }
th, td { border-bottom: 2px solid #dee2e6; padding: 7px 12px; text-align: left; vertical-align: top; }
th { background: #f1f3f5; }
code { font-family: Menlo, Consolas, monospace; font-size: 0.9em; background: #f1f3f5; padding: 0 5px; border-radius: 4px; }
.foot { position: absolute; bottom: 18px; left: 80px; right: 80px; font-size: 16px; color: #868e96;
  display: flex; justify-content: space-between; }
.notes { display: none; }
.ico { height: 1.05em; width: 1.05em; vertical-align: -0.18em; }
.picture h1 { font-size: 42px; margin-bottom: 4px; }
.picture .diagram { margin: 0; }
.picture .diagram img { width: auto; height: 580px; max-height: 580px; max-width: 1400px; }
.caption { font-size: 34px; line-height: 1.25; text-align: center; margin: 10px 0 0 0; font-weight: 600; }
.legend { display: flex; gap: 14px; flex-wrap: wrap; margin-top: 28px; }
.legend .pill { margin: 0; font-size: 22px; padding: 4px 16px; }
"""


def inline(text: str) -> str:
    out = html.escape(text, quote=False)
    out = re.sub(r"`([^`]+)`", r"<code>\1</code>", out)
    out = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", out)
    for token, svg in ICON_SVG.items():
        out = out.replace(token, svg)
    return out


def render_slide(raw: str, number: int, total: int) -> str:
    part = title = subtitle = ""
    bullets, notes, table_rows = [], [], []
    diagram = None
    legend = False
    picture = False
    in_notes = False
    for line in raw.strip("\n").split("\n"):
        s = line.rstrip()
        if in_notes:
            notes.append(s)
            continue
        if s.startswith("Notes:"):
            in_notes = True
            rest = s[len("Notes:"):].strip()
            if rest:
                notes.append(rest)
        elif s.startswith("Layout:"):
            picture = s[7:].strip() == "picture"
        elif s.startswith("Part:"):
            part = s[5:].strip()
        elif s.startswith("# "):
            title = s[2:].strip()
        elif s.startswith("## "):
            subtitle = s[3:].strip()
        elif s.startswith("!["):
            m = re.match(r"!\[(.*?)\]\((.*?)\)", s)
            if m:
                diagram = (m.group(1), m.group(2))
        elif s.startswith("|"):
            table_rows.append([c.strip() for c in s.strip("|").split("|")])
        elif s.startswith("- "):
            body = s[2:].strip()
            m = re.match(r"\[(\w+)\]\s*(.*)", body)
            tag = m.group(1) if m else None
            if m:
                body = m.group(2)
            bullets.append((tag, body))
        elif s.strip() == "{legend}":
            legend = True
    classes = "slide" + ("" if diagram else " nodiagram") + (" picture" if picture else "")
    parts = ['<section class="%s">' % classes]
    if part:
        parts.append('<div class="part">%s</div>' % inline(part))
    parts.append("<h1>%s</h1>" % inline(title))
    if subtitle and not picture:
        parts.append("<h2>%s</h2>" % inline(subtitle))
    if diagram:
        parts.append('<div class="diagram"><img src="%s" alt="%s"></div>'
                     % (html.escape(diagram[1]), html.escape(diagram[0])))
    if subtitle and picture:
        parts.append('<p class="caption">%s</p>' % inline(subtitle))
    if table_rows:
        parts.append("<table>")
        for i, row in enumerate(table_rows):
            if all(re.fullmatch(r":?-{2,}:?", c) for c in row):
                continue
            cell = "th" if i == 0 else "td"
            parts.append("<tr>%s</tr>" % "".join("<%s>%s</%s>" % (cell, inline(c), cell) for c in row))
        parts.append("</table>")
    if bullets:
        parts.append("<ul>")
        for tag, body in bullets:
            pill = ""
            if tag:
                if tag not in TAGS:
                    raise SystemExit("unknown tag [%s] on slide %d" % (tag, number))
                pill = '<span class="pill %s">%s</span>' % (tag, TAGS[tag])
            parts.append("<li%s>%s%s</li>" % (' class="tagged"' if pill else "", pill, inline(body)))
        parts.append("</ul>")
    if legend:
        parts.append('<div class="legend">%s</div>' % "".join(
            '<span class="pill %s">%s</span>' % (k, v) for k, v in TAGS.items()))
    if notes:
        parts.append('<div class="notes">%s</div>' % inline("\n".join(notes)).replace("\n", "<br>"))
    parts.append('<div class="foot"><span>Sandbox security concept | working draft</span><span>%d / %d</span></div>'
                 % (number, total))
    parts.append("</section>")
    return "\n".join(parts)


def main() -> None:
    here = Path(__file__).resolve().parent
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else here / "deck.md"
    dst = Path(sys.argv[2]) if len(sys.argv) > 2 else here / "deck.html"
    text = src.read_text(encoding="utf-8")
    slides = [b for b in re.split(r"(?m)^---\s*$", text) if b.strip()]
    body = "\n".join(render_slide(b, i + 1, len(slides)) for i, b in enumerate(slides))
    dst.write_text(
        '<!doctype html>\n<html lang="en"><head><meta charset="utf-8">'
        "<title>How dmfdeploy keeps secrets safe, and how it starts up</title>"
        "<style>%s</style></head><body>\n%s\n</body></html>\n" % (CSS, body),
        encoding="utf-8",
    )
    print("wrote %s (%d slides)" % (dst, len(slides)))


if __name__ == "__main__":
    main()
