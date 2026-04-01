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

# ax_ensure_topic_file PROJECT_ROOT TOPIC TEMPLATE_FILE
# Bootstraps a topic file from template if it doesn't exist yet.
ax_ensure_topic_file() {
  local project_root="$1"
  local topic="$2"      # e.g. "research-notes", "experiment-log", "decisions"
  local template="$3"   # absolute path to template file
  local topic_file="$project_root/.ax/memory/${topic}.md"

  [ -f "$topic_file" ] && return 0
  [ -f "$template" ] || return 1

  local slug
  slug=$(basename "$project_root")
  local slug_escaped
  slug_escaped=$(printf '%s' "$slug" | sed 's/[&\]/\\&/g')
  sed "s/{{project_slug}}/$slug_escaped/g" "$template" > "$topic_file"
}

# ax_get_topic_section PROJECT_ROOT TOPIC SECTION
# Reads a section from a topic file (research-notes.md, experiment-log.md, decisions.md).
ax_get_topic_section() {
  local project_root="$1"
  local topic="$2"
  local section="$3"
  local topic_file="$project_root/.ax/memory/${topic}.md"

  [ -f "$topic_file" ] || return 0
  ax_get_section "$topic_file" "$section"
}

# ax_replace_topic_section PROJECT_ROOT TOPIC SECTION CONTENT_FILE
# Replaces a section in a topic file.
ax_replace_topic_section() {
  local project_root="$1"
  local topic="$2"
  local section="$3"
  local content_file="$4"
  local topic_file="$project_root/.ax/memory/${topic}.md"

  [ -f "$topic_file" ] || return 1
  ax_replace_section "$topic_file" "$section" "$content_file"
}
