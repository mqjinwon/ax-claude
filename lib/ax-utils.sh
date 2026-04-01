#!/usr/bin/env bash
# AX shared utilities — sourced by adapters

# ax_replace_section FILE SECTION CONTENT_FILE
# Replaces content between <!-- BEGIN:SECTION --> and <!-- END:SECTION -->
# with the contents of CONTENT_FILE (avoids awk -v multiline issues)
ax_replace_section() {
  local file="$1"
  local section="$2"
  local content_file="$3"
  local tmp
  tmp=$(mktemp)

  awk -v section="$section" -v cf="$content_file" '
    BEGIN {
      skip=0
      begin_m = "<!-- BEGIN:" section " -->"
      end_m   = "<!-- END:" section " -->"
    }
    $0 == begin_m {
      print
      while ((getline line < cf) > 0) print line
      close(cf)
      skip=1
      next
    }
    $0 == end_m { skip=0 }
    !skip        { print }
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}

# ax_get_entry_ids FILE SECTION
# Prints existing entry IDs inside a section (one per line)
ax_get_entry_ids() {
  local file="$1"
  local section="$2"
  awk -v section="$section" '
    BEGIN {
      in_s=0
      begin_m = "<!-- BEGIN:" section " -->"
      end_m   = "<!-- END:" section " -->"
    }
    $0 == begin_m { in_s=1; next }
    $0 == end_m   { in_s=0 }
    in_s && /^<!-- entry:/ {
      id=$0
      sub(/^<!-- entry:/, "", id)
      sub(/ -->.*$/, "", id)
      print id
    }
  ' "$file" 2>/dev/null
}

# ax_get_section FILE SECTION
# Prints raw content between section markers (excluding the markers themselves)
ax_get_section() {
  local file="$1"
  local section="$2"
  awk -v section="$section" '
    BEGIN {
      in_s=0
      begin_m = "<!-- BEGIN:" section " -->"
      end_m   = "<!-- END:" section " -->"
    }
    $0 == begin_m { in_s=1; next }
    $0 == end_m   { in_s=0 }
    in_s          { print }
  ' "$file" 2>/dev/null
}
