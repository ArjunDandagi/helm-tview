#!/usr/bin/env bash
set -euo pipefail

HELM_BIN=${HELM_BIN:-helm}

show_help() {
  cat <<'EOF'
Helm TUI Template Viewer (tview)

Usage:
  helm tview [NAME] [CHART] [flags]

Flags:
  -s, --search STRING   Only list files containing STRING and highlight matches in preview

Examples:
  helm tview myrelease ./chart -f values.yaml
  helm tview myrelease bitnami/nginx --set image.tag=latest

Notes:
  - Behaves like 'helm template' but writes manifests to a temporary directory
    and opens a TUI browser so you can preview each output file individually.
  - Any provided --output-dir is ignored (the plugin manages its own temp dir).
EOF
}

sanitize_release_name() {
  local input="$1"
  local name
  name=$(printf '%s' "$input" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9-]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')
  if [[ -z "$name" ]]; then
    name="release"
  fi
  name="${name:0:53}"
  while [[ -n "$name" && "$name" =~ [^a-z0-9]$ ]]; do
    name="${name%?}"
  done
  if [[ -z "$name" ]]; then
    name="release"
  fi
  printf '%s' "$name"
}

for arg in "$@"; do
  case "$arg" in
    -h|--help) show_help; exit 0 ;;
  esac
done

WORK_DIR=$(mktemp -d -t helm-tview-XXXXXX)
OUT_DIR="$WORK_DIR/out"
mkdir -p "$OUT_DIR"

cleanup() {
  if [[ "${DEBUG:-}" != "" ]]; then
    echo "[tview] Temp dir preserved at: $OUT_DIR" >&2
  else
    rm -rf "$WORK_DIR" || true
  fi
}
trap cleanup EXIT

CLEAN_ARGS=()
SKIP_NEXT=0
EXPECTING_SEARCH=0
SEARCH_PAT=""
for arg in "$@"; do
  if [[ $SKIP_NEXT -eq 1 ]]; then
    SKIP_NEXT=0
    continue
  fi
  if [[ $EXPECTING_SEARCH -eq 1 ]]; then
    SEARCH_PAT="$arg"
    EXPECTING_SEARCH=0
    continue
  fi
  case "$arg" in
    --output-dir)
      SKIP_NEXT=1
      ;;
    --output-dir=*)
      ;;
    -s|--search)
      EXPECTING_SEARCH=1
      ;;
    --search=*)
      SEARCH_PAT="${arg#--search=}"
      ;;
    *)
      CLEAN_ARGS+=("$arg")
      ;;
  esac
done
export TVIEW_SEARCH="$SEARCH_PAT"

POSITIONAL=()
for a in "${CLEAN_ARGS[@]}"; do
  if [[ "$a" != -* ]]; then
    POSITIONAL+=("$a")
  fi
done
INVOKE_ARGS=("${CLEAN_ARGS[@]}")
if (( ${#POSITIONAL[@]} == 1 )); then
  local_chart_arg="${POSITIONAL[0]}"
  base="${local_chart_arg%/}"
  base="${base##*/}"
  base="${base%.tgz}"
  base="${base%.tar.gz}"
  default_name="$(sanitize_release_name "$base")"
  INVOKE_ARGS=("$default_name" "${CLEAN_ARGS[@]}")
fi
if (( ${#POSITIONAL[@]} == 0 )); then
  echo "[tview] Usage: helm tview [NAME] [CHART] [flags]" >&2
  echo "        Example: helm tview myrel ./chart -f values.yaml" >&2
  exit 1
fi

chart_arg=""
if (( ${#POSITIONAL[@]} >= 2 )); then
  chart_arg="${POSITIONAL[-1]}"
elif (( ${#POSITIONAL[@]} == 1 )); then
  chart_arg="${POSITIONAL[0]}"
fi

if [[ -n "$chart_arg" ]]; then
  if [[ -d "$chart_arg" ]]; then
    if [[ ! -f "$chart_arg/Chart.yaml" ]]; then
      echo "[tview] '$chart_arg' is not a Helm chart directory (missing Chart.yaml)." >&2
      echo "        cd into your chart or pass the chart path, e.g.: helm tview myrel ./path/to/chart" >&2
      exit 1
    fi
  fi
fi

if ! "$HELM_BIN" template "${INVOKE_ARGS[@]}" --output-dir "$OUT_DIR" >/dev/null; then
  echo "[tview] Failed to render templates via: $HELM_BIN template ${INVOKE_ARGS[*]}" >&2
  exit 1
fi

LIST_FILE="$WORK_DIR/files.txt"
> "$LIST_FILE"
BOLD=$'\033[1m'; DIM=$'\033[2m'; CYAN=$'\033[36m'; RESET=$'\033[0m'
find "$OUT_DIR" -type f | sort | while IFS= read -r f; do
  rel=${f#"$OUT_DIR/"}
  base=${rel##*/}
  dir=${rel%/*}
  [[ "$dir" == "$rel" ]] && dir=""
  kind=$(grep -m1 -E '^[[:space:]]*kind:[[:space:]]*' "$f" | sed -E 's/^[[:space:]]*kind:[[:space:]]*//; s/[[:space:]]+$//' || true)
  label_plain="$base"
  [[ -n "$dir" ]] && label_plain+="  — $dir"
  [[ -n "$kind" ]] && label_plain+="  [$kind]"
  label_ansi="${BOLD}${base}${RESET}"
  [[ -n "$dir" ]] && label_ansi+="  ${DIM}${dir}${RESET}"
  [[ -n "$kind" ]] && label_ansi+="  ${CYAN}[${kind}]${RESET}"
  printf '%s\t%s\t%s\n' "$label_plain" "$label_ansi" "$f" >> "$LIST_FILE"
done
if ! [[ -s "$LIST_FILE" ]]; then
  echo "[tview] No files were produced by helm template." >&2
  exit 1
fi

# Build search matches file if requested
MATCH_FILE="$WORK_DIR/matches.txt"
if [[ -n "$TVIEW_SEARCH" ]]; then
  > "$MATCH_FILE"
  if command -v rg >/dev/null 2>&1; then
    MATCHED=$(rg -l -S -e "$TVIEW_SEARCH" "$OUT_DIR" || true)
  else
    MATCHED=$(grep -R -l -- "$TVIEW_SEARCH" "$OUT_DIR" || true)
  fi
  if [[ -n "$MATCHED" ]]; then
    while IFS= read -r mf; do
      [[ -z "$mf" ]] && continue
      rel=${mf#"$OUT_DIR/"}
      base=${rel##*/}
      dir=${rel%/*}
      [[ "$dir" == "$rel" ]] && dir=""
      kind=$(grep -m1 -E '^[[:space:]]*kind:[[:space:]]*' "$mf" | sed -E 's/^[[:space:]]*kind:[[:space:]]*//; s/[[:space:]]+$//' || true)
      label_plain="$base"; [[ -n "$dir" ]] && label_plain+="  — $dir"; [[ -n "$kind" ]] && label_plain+="  [$kind]"
      label_ansi="${BOLD}${base}${RESET}"; [[ -n "$dir" ]] && label_ansi+="  ${DIM}${dir}${RESET}"; [[ -n "$kind" ]] && label_ansi+="  ${CYAN}[${kind}]${RESET}"
      printf '%s\t%s\t%s\n' "$label_plain" "$label_ansi" "$mf" >> "$MATCH_FILE"
    done <<< "$MATCHED"
  fi
fi

BAT_CMD=""
if command -v bat >/dev/null 2>&1; then
  BAT_CMD="bat"
elif command -v batcat >/dev/null 2>&1; then
  BAT_CMD="batcat"
fi

open_cmd() {
  if [[ -n "$BAT_CMD" ]]; then
    "$BAT_CMD" --style=header,numbers --paging=always "$1" || less -R "$1"
  else
    ${PAGER:-less -R} "$1"
  fi
}

if command -v fzf >/dev/null 2>&1; then
  FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:-} --layout=reverse --border --height=100%"
  SELECT_SOURCE="$LIST_FILE"; [[ -n "$TVIEW_SEARCH" && -s "$MATCH_FILE" ]] && SELECT_SOURCE="$MATCH_FILE"
  SELECTED=$(cat "$SELECT_SOURCE" | FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS" fzf \
    --ansi \
    --delimiter='\t' --with-nth=2 \
    --prompt='tview> ' \
    --header=$([[ -n "$TVIEW_SEARCH" ]] && printf '%q' "Search: $TVIEW_SEARCH  •  Navigate with arrows • Enter: open • ESC: quit" || printf '%q' 'Navigate with arrows • Enter: open • ESC: quit') \
    --preview-window='right,70%,border-left' \
    --preview 'bash -lc '\''f="{3}"; if [[ -f "$f" ]]; then if [[ -n "${TVIEW_SEARCH:-}" ]] && command -v rg >/dev/null 2>&1; then rg --color=always -n -S --passthru -e "${TVIEW_SEARCH}" "$f" | sed -n "1,400p"; else if command -v bat >/dev/null 2>&1; then bat --style=header,numbers --color=always --paging=never "$f"; else sed -n "1,400p" "$f"; fi; fi; fi'\''
  ) || true
  if [[ -n "${SELECTED:-}" ]]; then
    sel_path=$(printf '%s' "$SELECTED" | awk -F '\t' '{print $3}')
    if [[ -n "$sel_path" ]]; then
      open_cmd "$sel_path"
    fi
  fi
  exit 0
fi

# Fallback menu
LABELS=()
PATHS=()
SELECT_SOURCE_FILE="$LIST_FILE"; [[ -n "$TVIEW_SEARCH" && -s "$MATCH_FILE" ]] && SELECT_SOURCE_FILE="$MATCH_FILE"
while IFS=$'\t' read -r label _ path; do
  LABELS+=("$label")
  PATHS+=("$path")
done < "$SELECT_SOURCE_FILE"

while true; do
  echo ""
  echo "Select a file to view (q to quit):"
  i=1
  for label in "${LABELS[@]}"; do
    printf "  %2d) %s\n" "$i" "$label"
    ((i++))
  done
  echo -n "> "
  read -r choice || break
  case "$choice" in
    q|Q|quit|exit) break ;;
    '' ) continue ;;
    * )
      if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#PATHS[@]} )); then
        sel_path=${PATHS[choice-1]}
        open_cmd "$sel_path"
      else
        echo "Invalid selection" >&2
      fi
      ;;
  esac
done
