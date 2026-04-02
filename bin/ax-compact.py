#!/usr/bin/env python3
# ax-compact.py — Rolling Summary + Hard Cap compaction for a topic-file section
# Usage: python3 ax-compact.py <topic_file> <section> <hard_cap> <keep_recent>
#
# If entry count in section > hard_cap:
#   - Keeps newest <keep_recent> entries verbatim
#   - Replaces older entries with one compact notice entry
#   - Writes new section body to a temp file, prints its path to stdout
#
# Exits 0 with no output when compaction is not needed.

import datetime
import re
import sys
import tempfile

if len(sys.argv) != 5:
    print(f"Usage: {sys.argv[0]} <topic_file> <section> <hard_cap> <keep_recent>", file=sys.stderr)
    sys.exit(1)

topic_file, section = sys.argv[1], sys.argv[2]
hard_cap, keep_recent = int(sys.argv[3]), int(sys.argv[4])

try:
    with open(topic_file) as f:
        content = f.read()
except OSError:
    sys.exit(0)

begin_marker = f"<!-- BEGIN:{section} -->"
end_marker = f"<!-- END:{section} -->"

begin_idx = content.find(begin_marker)
end_idx = content.find(end_marker)
if begin_idx == -1 or end_idx == -1:
    sys.exit(0)

section_body = content[begin_idx + len(begin_marker):end_idx]

# Split into (marker, body) pairs on <!-- entry:... --> boundaries
entry_re = re.compile(r"(<!-- entry:[^>]+ -->)")
parts = entry_re.split(section_body)

entries = []  # list of (marker_str, body_str)
i = 1
while i < len(parts):
    marker = parts[i]
    body = parts[i + 1] if i + 1 < len(parts) else ""
    entries.append((marker, body))
    i += 2

if len(entries) <= hard_cap:
    sys.exit(0)

compress_count = len(entries) - keep_recent
to_compress = entries[:compress_count]
to_keep = entries[compress_count:]

today = datetime.date.today().strftime("%Y-%m-%d")
ts = datetime.datetime.now().strftime("%Y%m%d%H%M")

# Build one-line summaries for the compact notice
summaries = []
for marker, body in to_compress:
    m = re.search(r"<!-- entry:([^>]+) -->", marker)
    entry_id = m.group(1) if m else ""

    # Fold existing compact notices — re-use their summary lines
    if entry_id.startswith("compact-"):
        for line in body.strip().splitlines():
            if line.startswith("- "):
                summaries.append(line)
        continue

    # Extract first meaningful line from body
    first_line = ""
    for line in body.strip().splitlines():
        stripped = line.strip()
        if stripped and not stripped.startswith("<!--"):
            first_line = stripped
            break

    date_match = re.match(r"\*\*(\d{4}-\d{2}-\d{2})\*\*", first_line)
    if date_match:
        entry_date = date_match.group(1)
        rest = first_line[date_match.end():].strip().lstrip(": ")
        # Strip inline code/bold noise for readability
        rest = re.sub(r"`[^`]*`", "", rest).strip().lstrip(": ")
        summaries.append(f"- [{entry_date}] {rest[:120]}")
    elif first_line.startswith("- "):
        summaries.append(first_line[:120])
    else:
        summaries.append(f"- {first_line[:120]}")

# Determine date range of compressed entries
dates = []
for _, body in to_compress:
    dm = re.search(r"\*\*(\d{4}-\d{2}-\d{2})\*\*", body)
    if dm:
        dates.append(dm.group(1))
date_range = f"{min(dates)}..{max(dates)}" if dates else today

compact_notice = (
    f"<!-- entry:compact-{ts} -->\n"
    f"**{today}** [compacted {len(to_compress)} entries, {date_range}]:\n"
    + "\n".join(summaries[:30])  # guard against runaway growth
    + "\n\n"
)

# Rebuild section body: compact notice first, then kept entries
new_body = "\n" + compact_notice
for marker, body in to_keep:
    new_body += marker + body

tmp = tempfile.NamedTemporaryFile(mode="w", suffix=".ax-compact", delete=False)
tmp.write(new_body)
tmp.close()
print(tmp.name)
