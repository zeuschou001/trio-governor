#!/usr/bin/env bash

escape_sed() {
  printf '%s' "$1" | sed 's/[&|\\]/\\&/g'
}

doc_render_template() {
  local tmpl="$1" out="$2" version_value="$3" timestamp_value="$4" name_value="$5" type_value="$6" created_at_value="$7" description_value="$8"
  local tmp=''
  tmp="$out.tmp.$$"
  sed \
    -e "s|{{version}}|$(escape_sed "$version_value")|g" \
    -e "s|{{timestamp}}|$(escape_sed "$timestamp_value")|g" \
    -e "s|{{name}}|$(escape_sed "$name_value")|g" \
    -e "s|{{type}}|$(escape_sed "$type_value")|g" \
    -e "s|{{created_at}}|$(escape_sed "$created_at_value")|g" \
    -e "s|{{description}}|$(escape_sed "$description_value")|g" \
    "$tmpl" >"$tmp"
  if grep -q '{{' "$tmp"; then
    rm -f "$tmp"
    printf '模板占位符未全部替换,拒绝写入\n' >&2
    return 1
  fi
  python3 -c 'import os,sys; f=open(sys.argv[1], "rb"); os.fsync(f.fileno()); f.close()' "$tmp"
  mv "$tmp" "$out"
}

doc_write_signature() {
  local trio_dir="$1"
  doc_render_template "$TEMPLATE_DIR/.trio-signature.tmpl" "$trio_dir/.trio-signature" "$VERSION_VALUE" "$(ts_utc)" '' '' '' ''
}

doc_write_skeleton() {
  local trio_dir="$1" file="$2"
  case "$file" in
    PROJECT.md)
      doc_render_template "$TEMPLATE_DIR/PROJECT.md.tmpl" "$trio_dir/PROJECT.md" "$VERSION_VALUE" "$(ts_utc)" '' '' '' ''
      ;;
    DECISIONS.md)
      doc_render_template "$TEMPLATE_DIR/DECISIONS.md.tmpl" "$trio_dir/DECISIONS.md" "$VERSION_VALUE" "$(ts_utc)" '' '' '' ''
      ;;
    KNOWLEDGE.md)
      doc_render_template "$TEMPLATE_DIR/KNOWLEDGE.md.tmpl" "$trio_dir/KNOWLEDGE.md" "$VERSION_VALUE" "$(ts_utc)" '' '' '' ''
      ;;
    ROADMAP.md)
      doc_render_template "$TEMPLATE_DIR/ROADMAP.md.tmpl" "$trio_dir/ROADMAP.md" "$VERSION_VALUE" "$(ts_utc)" '' '' '' ''
      ;;
    *)
      return 1
      ;;
  esac
}

doc_to_epoch() {
  local v="$1"
  date -u -d "$v" +%s 2>/dev/null || date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$v" +%s 2>/dev/null
}

doc_last_decision_timestamp() {
  local file="$1" title="$2" type="$3"
  awk -v wt="$title" -v wtype="$type" '
    function flush() {
      if (in_block && t == wt && ty == wtype && ts != "") last = ts
    }
    /^## Decision: / {
      flush(); in_block = 1
      t = $0; sub(/^## Decision: /, "", t)
      ty = ""; ts = ""; next
    }
    /^## / { flush(); in_block = 0; next }
    in_block {
      if ($0 ~ /^- \*\*Timestamp\*\*: /) { ts = $0; sub(/^- \*\*Timestamp\*\*: /, "", ts) }
      else if ($0 ~ /^- \*\*Type\*\*: /) { ty = $0; sub(/^- \*\*Type\*\*: /, "", ty) }
    }
    END { flush(); if (last != "") print last }
  ' "$file"
}

doc_project_frontmatter_value() {
  local file="$1" key="$2"
  sed -n "s/^$key: \"\\(.*\\)\"$/\\1/p" "$file" | head -n 1
}

doc_project_write() {
  local trio_dir="$1" name="$2" type="$3" description="$4" file=''
  file="$trio_dir/PROJECT.md"
  [ -f "$file" ] || { printf 'PROJECT.md 不存在\n' >&2; return 1; }
  local cur_name cur_type cur_created cur_desc
  cur_name="$(doc_project_frontmatter_value "$file" name)"
  cur_type="$(doc_project_frontmatter_value "$file" type)"
  cur_created="$(doc_project_frontmatter_value "$file" created_at)"
  cur_desc="$(doc_project_frontmatter_value "$file" description)"
  if [ -n "$cur_name$cur_type$cur_created$cur_desc" ]; then
    printf 'PROJECT.md frontmatter 已 seal,请改用 Addendum\n' >&2
    return 1
  fi
  doc_render_template "$TEMPLATE_DIR/PROJECT.md.tmpl" "$file" "$VERSION_VALUE" "$(ts_utc)" "$name" "$type" "$(ts_utc)" "$description"
}

doc_decision_append() {
  local trio_dir="$1" dtype="$2" title="$3" what="$4" why="$5" impact="$6"
  case "$dtype" in
    eng-review|ceo-review) ;;
    *)
      printf '用法: %s <宿主项目目录> <type> <title> <what> <why> <impact>\n' "decision-append" >&2
      return 2
      ;;
  esac
  [ -f "$trio_dir/.trio-signature" ] && [ -f "$trio_dir/DECISIONS.md" ] || return 1

  mkdir -p "$trio_dir/.locks"
  exec 7>"$trio_dir/.locks/DECISIONS.md.lock"
  if ! flock -x -w 5 7; then
    printf '并发写入冲突\n' >&2
    return 5
  fi

  local timestamp now_epoch last_ts last_epoch delta abs
  timestamp="$(ts_utc)"
  now_epoch="$(doc_to_epoch "$timestamp")"
  last_ts="$(doc_last_decision_timestamp "$trio_dir/DECISIONS.md" "$title" "$dtype")"
  if [ -n "$last_ts" ]; then
    if last_epoch="$(doc_to_epoch "$last_ts")" && [ -n "$last_epoch" ]; then
      delta=$((now_epoch - last_epoch))
      abs=${delta#-}
      if [ "$abs" -lt 5 ]; then
        printf '检测到重复决策条目(相同标题+类型且 Timestamp 间距 < 5s),已跳过\n'
        return 0
      fi
    fi
  fi

  printf '\n## Decision: %s\n- **Timestamp**: %s\n- **Type**: %s\n- **What**: %s\n- **Why**: %s\n- **Impact**: %s\n' \
    "$title" "$timestamp" "$dtype" "$what" "$why" "$impact" >>"$trio_dir/DECISIONS.md"
}

doc_decision_has_complete_type() {
  local file="$1" dtype="$2"
  awk -v want="$dtype" '
    function flush() {
      if (in_block && ty == want && has_what && has_why && has_impact) found = 1
    }
    /^## Decision: / {
      flush()
      in_block = 1
      ty = ""
      has_what = 0
      has_why = 0
      has_impact = 0
      next
    }
    /^## / {
      flush()
      in_block = 0
      next
    }
    in_block {
      if ($0 ~ /^- \*\*Type\*\*: /) { ty = $0; sub(/^- \*\*Type\*\*: /, "", ty) }
      else if ($0 ~ /^- \*\*What\*\*: /) { has_what = 1 }
      else if ($0 ~ /^- \*\*Why\*\*: /) { has_why = 1 }
      else if ($0 ~ /^- \*\*Impact\*\*: /) { has_impact = 1 }
    }
    END {
      flush()
      exit(found ? 0 : 1)
    }
  ' "$file"
}

doc_knowledge_append() {
  local trio_dir="$1" title="$2" context="$3" takeaway="$4"
  [ -f "$trio_dir/.trio-signature" ] && [ -f "$trio_dir/KNOWLEDGE.md" ] || return 1
  mkdir -p "$trio_dir/.locks"
  exec 7>"$trio_dir/.locks/KNOWLEDGE.md.lock"
  if ! flock -x -w 5 7; then
    printf '并发写入冲突\n' >&2
    return 5
  fi
  printf '\n## Insight: %s\n- **Learned-at**: %s\n- **Context**: %s\n- **Takeaway**: %s\n' \
    "$title" "$(ts_utc)" "$context" "$takeaway" >>"$trio_dir/KNOWLEDGE.md"
}

doc_archive_path() {
  local trio_dir="$1" prefix="$2" stamp base candidate i
  mkdir -p "$trio_dir/archive"
  stamp="$(archive_stamp)"
  base="$trio_dir/archive/${prefix}-${stamp}.md"
  candidate="$base"
  i=1
  while [ -e "$candidate" ]; do
    candidate="$trio_dir/archive/${prefix}-${stamp}-$i.md"
    i=$((i + 1))
  done
  printf '%s\n' "$candidate"
}

doc_roadmap_rewrite() {
  local trio_dir="$1" input="$2" file='' archive='' target='' tmp=''
  file="$trio_dir/ROADMAP.md"
  [ -f "$trio_dir/.trio-signature" ] || return 1
  if [ -f "$file" ]; then
    archive="$(doc_archive_path "$trio_dir" ROADMAP)"
    cp "$file" "$archive"
  fi
  target="$file"
  tmp="$target.tmp.$$"
  if [ "$input" = '--' ]; then
    cat >"$tmp"
  else
    cat "$input" >"$tmp"
  fi
  python3 -c 'import os,sys; f=open(sys.argv[1], "rb"); os.fsync(f.fileno()); f.close()' "$tmp"
  mv "$tmp" "$target"
}
