config=${ANDROID_AUDIO_ORIENTATION_CONFIG:-/etc/android-audio-orientation.json}

usage() {
  cat <<'EOF'
Usage: android-audio-orientation apply <normal|90|180|270>
       android-audio-orientation restore [SECONDS]
       android-audio-orientation status

apply    set the speaker routing controls described for an orientation
restore  apply the last recorded orientation (default normal), then keep it
         for SECONDS (default 15) while the audio profile is being activated
status   print the recorded orientation and the current control values
EOF
}

die() {
  printf 'android-audio-orientation: %s\n' "$*" >&2
  exit 1
}

state_file() {
  if [ -n "${XDG_RUNTIME_DIR:-}" ]; then
    printf '%s/android-audio-orientation\n' "$XDG_RUNTIME_DIR"
  elif [ "$(id -u)" = 0 ]; then
    printf '/run/android-audio-orientation\n'
  else
    die "XDG_RUNTIME_DIR is required"
  fi
}

check_orientation() {
  case "$1" in
    normal | 90 | 180 | 270) ;;
    flipped*) die "flipped transform $1 mirrors the image; no speaker routing applies" ;;
    *) die "unknown orientation '$1' (expected normal, 90, 180 or 270)" ;;
  esac
}

# Tab-separated card, control and value of every entry for one orientation.
entries() {
  jq -r --arg o "$1" '(.orientations[$o] // [])[] | [.card, .control, (.value | tostring)] | @tsv' \
    "$config"
}

# Every control named by any orientation, once.
all_controls() {
  jq -r '[.orientations[][] | [.card, .control]] | unique[] | @tsv' "$config"
}

# The control's value as amixer reports it, e.g. `values=1`.
current() {
  amixer -c "$1" cget "name=$2" 2>/dev/null | sed -n 's/^ *: values=//p'
}

# Whether the control already has the value; enum values may be item names.
has_value() {
  local card=$1 control=$2 value=$3 info index
  info=$(amixer -c "$card" cget "name=$control" 2>/dev/null) || return 1
  index=$value
  if ! [[ $value =~ ^-?[0-9]+$ ]]; then
    index=$(sed -n "s/^ *; Item #\([0-9]*\) '\(.*\)'\$/\1 \2/p" <<<"$info" \
      | while read -r number name; do
        if [ "$name" = "$value" ]; then printf '%s\n' "$number"; fi
      done)
  fi
  [ -n "$index" ] && [ "$(sed -n 's/^ *: values=//p' <<<"$info")" = "$index" ]
}

# Set the routing for an orientation. With `quiet`, print only changes.
route() {
  local orientation=$1 mode=${2:-} card control value list
  list=$(entries "$orientation")
  if [ -z "$list" ]; then
    [ "$mode" = quiet ] || printf 'no speaker routing described for %s; unchanged\n' "$orientation"
    return 0
  fi
  # Check every control first so an unknown one changes nothing.
  while IFS=$'\t' read -r card control value; do
    amixer -c "$card" cget "name=$control" >/dev/null 2>&1 \
      || die "card $card has no control '$control'"
  done <<<"$list"
  while IFS=$'\t' read -r card control value; do
    if [ "$mode" = quiet ] && has_value "$card" "$control" "$value"; then
      continue
    fi
    amixer -q -c "$card" cset "name=$control" "$value" \
      || die "failed to set $card '$control' to $value"
    printf '%s: %s = %s\n' "$card" "$control" "$value"
  done <<<"$list"
}

record() {
  local file
  file=$(state_file)
  printf '%s\n' "$1" >"$file.tmp"
  mv "$file.tmp" "$file"
}

recorded() {
  local file value
  file=$(state_file)
  value=$(cat "$file" 2>/dev/null || true)
  case "$value" in
    normal | 90 | 180 | 270) printf '%s\n' "$value" ;;
    *) printf 'normal\n' ;;
  esac
}

[ -r "$config" ] || die "cannot read $config"
command=${1:-}
case "$command" in
  apply)
    [ $# -eq 2 ] || { usage >&2; exit 2; }
    check_orientation "$2"
    exec 9>"$(state_file).lock"
    flock 9
    printf 'applying speaker routing for %s\n' "$2"
    route "$2"
    record "$2"
    ;;
  restore)
    [ $# -le 2 ] || { usage >&2; exit 2; }
    settle=${2:-15}
    [[ $settle =~ ^[0-9]+$ ]] || die "invalid settle time '$settle'"
    # Activating the audio profile can rewrite the controls after this starts;
    # recheck each second and follow orientations applied in the meantime.
    for ((elapsed = 0; elapsed <= settle; elapsed++)); do
      exec 9>"$(state_file).lock"
      flock 9
      orientation=$(recorded)
      if [ "$elapsed" = 0 ]; then
        printf 'restoring speaker routing for %s\n' "$orientation"
      fi
      route "$orientation" quiet
      exec 9>&-
      if [ "$elapsed" -lt "$settle" ]; then sleep 1; fi
    done
    ;;
  status)
    [ $# -eq 1 ] || { usage >&2; exit 2; }
    file=$(state_file)
    printf 'orientation: %s\n' "$(cat "$file" 2>/dev/null || printf 'none recorded')"
    while IFS=$'\t' read -r card control; do
      printf '%s: %s = %s\n' "$card" "$control" "$(current "$card" "$control" || true)"
    done < <(all_controls)
    ;;
  -h | --help | help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
