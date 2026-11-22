#!/usr/bin/env bash
# Tests for the pinentry-tmux shim.
#
#   ./test.sh [path/to/pinentry.sh]
#
# Tests 1-6 (stubs): verify ttyname rewriting for pane, client, and unusable
# ttys, pass-through for plain terminals, the no-client failure, and popup
# teardown.
# Tests 7-9 (stubs): verify the popup follows the newest client across
# sessions and the Qt prompt uses the requesting terminal's display.
# Tests 10-11 (integration): verify the popup dance against a real isolated tmux
# server with a scripted attached client (skipped when tmux/script are absent).
#
# The tests deliberately target an isolated tmux server via an unset $TMUX and
# a private $TMUX_TMPDIR. Never run tmux against the ambient server here.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
shim="${1:-$here/pinentry.sh}"

# Detach from any ambient tmux; all test tmux calls use the private socket dir
# below. `env -u TMUX` on shim invocations keeps the shim on that server too.
unset TMUX TMUX_PANE TMUX_TMPDIR

tmp="$(mktemp -d)"
test_sock="$tmp/sock"

tmux_test() { TMUX_TMPDIR="$test_sock" env -u TMUX tmux "$@"; }

cleanup() {
  if [ -s "$tmp/pids" ]; then
    xargs kill < "$tmp/pids" 2> /dev/null || true
  fi
  tmux_test kill-server 2> /dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

log_has() { grep -q "$1" "$2" || fail "$3"; }
log_lacks() { if grep -q "$1" "$2"; then fail "$3"; fi; }

mkdir -p "$tmp/stubtmux" "$tmp/stubpin"

# --- stub tmux -------------------------------------------------------------
cat > "$tmp/stubtmux/tmux" <<'EOF'
#!/usr/bin/env bash
sub="$1"; shift
case "$sub" in
  list-sessions)
    exit 0
    ;;
  list-clients)
    [ -n "${STUB_NO_CLIENTS:-}" ] && exit 0
    if [ -n "${STUB_CLIENTS:-}" ]; then
      printf '%s\n' "$STUB_CLIENTS"
    else
      printf '/dev/pts/46 test-session 1000\n'
    fi
    ;;
  list-panes)
    printf '%s test-session\n' "${STUB_PANE_TTY:-/dev/pts/16}"
    ;;
  display-popup)
    ttyfifo=""; donefifo=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -c)
          printf 'popup-client=%s\n' "$2" >> "$STUB_LOG"
          shift 2
          ;;
        -e)
          case "$2" in
            PINENTRY_TTY_FIFO=*) ttyfifo="${2#PINENTRY_TTY_FIFO=}" ;;
            PINENTRY_DONE_FIFO=*) donefifo="${2#PINENTRY_DONE_FIFO=}" ;;
          esac
          shift 2
          ;;
        *) shift ;;
      esac
    done
    printf '%s\n' "${STUB_POPUP_TTY:-/dev/pts/99}" > "$ttyfifo"
    read -r _ < "$donefifo"
    printf 'popup-closed\n' >> "$STUB_LOG"
    ;;
esac
EOF
chmod +x "$tmp/stubtmux/tmux"

# --- stub pinentry ---------------------------------------------------------
cat > "$tmp/stubpin/pinentry-curses" <<'EOF'
#!/usr/bin/env bash
printf 'OK stub\n'
while IFS= read -r line; do
  printf '%s\n' "$line" >> "$STUB_LOG"
  case "$line" in
    'OPTION ttyname='*)
      [ -c "${line#OPTION ttyname=}" ] && printf 'tty-exists\n' >> "$STUB_LOG"
      printf 'OK\n'
      ;;
    BYE*)
      printf 'OK bye\n'
      exit 0
      ;;
    *)
      printf 'OK\n'
      ;;
  esac
done
EOF
chmod +x "$tmp/stubpin/pinentry-curses"

# pinentry-qt only records which display it would have drawn on.
cat > "$tmp/stubpin/pinentry-qt" <<'EOF'
#!/usr/bin/env bash
printf 'qt runtime=%s wayland=%s\n' "${XDG_RUNTIME_DIR:-}" "${WAYLAND_DISPLAY:-}" >> "$STUB_LOG"
printf 'OK stub-qt\n'
while IFS= read -r line; do
  case "$line" in BYE*) printf 'OK bye\n'; exit 0 ;; esac
done
EOF
chmod +x "$tmp/stubpin/pinentry-qt"

stub_run() { # <log> <extra env>... -- reads stdin
  local log="$1"; shift
  env -u TMUX -u GPG_TTY -u WAYLAND_DISPLAY -u DISPLAY \
    PINENTRY_REMOTE_RUNTIME_DIR="$tmp/no-remote" \
    STUB_LOG="$log" "$@" PATH="$tmp/stubtmux:$tmp/stubpin:$PATH" "$shim"
}

# --- test 1: pane tty is rewritten to the popup tty ------------------------
: > "$tmp/log1"
printf 'OPTION ttyname=/dev/pts/16\nBYE\n' |
  stub_run "$tmp/log1" > "$tmp/out1" 2>&1 ||
  fail "shim exited nonzero (test 1)"

log_has '^OK stub$' "$tmp/out1" "pinentry greeting was not relayed"
log_has '^OPTION ttyname=/dev/pts/99$' "$tmp/log1" "pane ttyname was not rewritten to the popup tty"
log_has '^BYE$' "$tmp/log1" "BYE was not forwarded"
log_has '^popup-closed$' "$tmp/log1" "popup was not torn down"
echo "ok 1 - pane tty rewrite and teardown"

# --- test 2: client tty is rewritten to the popup tty ----------------------
: > "$tmp/log2"
printf 'OPTION ttyname=/dev/pts/46\nBYE\n' |
  stub_run "$tmp/log2" > "$tmp/out2" 2>&1 ||
  fail "shim exited nonzero (test 2)"

log_has '^OPTION ttyname=/dev/pts/99$' "$tmp/log2" "client ttyname was not rewritten to the popup tty"
log_has '^popup-closed$' "$tmp/log2" "popup was not opened for a client tty"
echo "ok 2 - client tty rewrite"

# --- test 3: plain terminal passes through unchanged -----------------------
: > "$tmp/log3"
printf 'OPTION ttyname=/dev/null\nBYE\n' |
  stub_run "$tmp/log3" > "$tmp/out3" 2>&1 ||
  fail "shim exited nonzero (test 3)"

log_has '^OPTION ttyname=/dev/null$' "$tmp/log3" "plain ttyname should pass through"
log_lacks '^popup-closed$' "$tmp/log3" "popup must not be opened for a plain terminal"
echo "ok 3 - plain terminal passes through"

# --- test 4: unusable tty falls back to the attached client ----------------
: > "$tmp/log4"
printf 'OPTION ttyname=/dev/pts/no-such-tty\nBYE\n' |
  stub_run "$tmp/log4" > "$tmp/out4" 2>&1 ||
  fail "shim exited nonzero (test 4)"

log_has '^OPTION ttyname=/dev/pts/99$' "$tmp/log4" "unusable ttyname was not rewritten to the popup tty"
log_has '^popup-closed$' "$tmp/log4" "popup was not opened for an unusable tty"
echo "ok 4 - unusable tty falls back to the attached client"

# --- test 5: no attached client fails fast ---------------------------------
: > "$tmp/log5"
if printf 'OPTION ttyname=/dev/pts/16\nBYE\n' |
  stub_run "$tmp/log5" STUB_NO_CLIENTS=1 > "$tmp/out5" 2> "$tmp/err5"; then
  fail "shim must fail when no client can show a popup"
fi

log_has 'no prompt surface' "$tmp/err5" "failure did not name the missing prompt surface"
log_lacks '^OPTION ttyname=' "$tmp/log5" "pinentry must not receive the option when the shim fails"
log_lacks '^popup-closed$' "$tmp/log5" "popup must not be opened without an attached client"
echo "ok 5 - no attached client fails fast"

# --- test 6: no attached client, plain terminal still passes through -------
: > "$tmp/log6"
printf 'OPTION ttyname=/dev/null\nBYE\n' |
  stub_run "$tmp/log6" STUB_NO_CLIENTS=1 > "$tmp/out6" 2>&1 ||
  fail "shim exited nonzero (test 6)"

log_has '^OPTION ttyname=/dev/null$' "$tmp/log6" "plain ttyname should pass through without a client"
log_lacks '^popup-closed$' "$tmp/log6" "popup must not be opened without an attached client"
echo "ok 6 - no client, plain terminal passes through"

# --- test 7: pane popup goes to the newest client, in any session ----------
# The pane's session is shown only by an idle client; the user last typed in
# a client of another session (the remote session, say).
: > "$tmp/log7"
printf 'OPTION ttyname=/dev/pts/16\nBYE\n' |
  stub_run "$tmp/log7" STUB_CLIENTS="$(printf '%s\n' \
    '/dev/pts/46 test-session 1000' \
    '/dev/pts/47 other-session 2000')" > "$tmp/out7" 2>&1 ||
  fail "shim exited nonzero (test 7)"

log_has '^popup-client=/dev/pts/47$' "$tmp/log7" "popup did not follow the most recently active client"
log_has '^OPTION ttyname=/dev/pts/99$' "$tmp/log7" "pane ttyname was not rewritten (test 7)"
echo "ok 7 - pane popup follows the newest client across sessions"

# --- tests 8-9: the Qt prompt uses the requesting terminal's display -------
# Both runtime dirs hold a wayland-1 socket, as the desktop and the remote
# session do. The agent's environment points at the desktop's.
if command -v script > /dev/null && command -v python3 > /dev/null; then
  mkdir -p "$tmp/rt-agent" "$tmp/rt-requester"
  for dir in "$tmp/rt-agent" "$tmp/rt-requester"; do
    python3 -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$dir/wayland-1"
  done

  # Hold a terminal open whose processes carry the given environment, and
  # print its tty.
  hold_tty() { # <name> <env assignments>...
    local name="$1"; shift
    env -i PATH="$PATH" "$@" script -qec 'tty > "$TTY_OUT"; exec sleep 30' /dev/null \
      < /dev/null > /dev/null 2>&1 &
    printf '%s\n' "$!" >> "$tmp/pids"
    for _ in $(seq 1 50); do
      [ -s "$tmp/$name.tty" ] && break
      sleep 0.1
    done
    [ -s "$tmp/$name.tty" ] || fail "could not open a test terminal ($name)"
    cat "$tmp/$name.tty"
  }

  remote_tty="$(hold_tty remote TTY_OUT="$tmp/remote.tty" \
    XDG_RUNTIME_DIR="$tmp/rt-requester" WAYLAND_DISPLAY=wayland-1)"
  : > "$tmp/log8"
  printf 'OPTION ttyname=%s\nBYE\n' "$remote_tty" |
    stub_run "$tmp/log8" STUB_NO_CLIENTS=1 GPG_TTY="$remote_tty" \
      XDG_RUNTIME_DIR="$tmp/rt-agent" WAYLAND_DISPLAY=wayland-1 > "$tmp/out8" 2>&1 ||
    fail "shim exited nonzero (test 8)"
  log_has "^qt runtime=$tmp/rt-requester wayland=wayland-1\$" "$tmp/log8" \
    "Qt prompt did not use the requesting terminal's display"
  echo "ok 8 - Qt prompt opens on the requesting terminal's display"

  bare_tty="$(hold_tty bare TTY_OUT="$tmp/bare.tty" XDG_RUNTIME_DIR="$tmp/rt-requester")"
  : > "$tmp/log9"
  printf 'OPTION ttyname=%s\nBYE\n' "$bare_tty" |
    stub_run "$tmp/log9" STUB_NO_CLIENTS=1 GPG_TTY="$bare_tty" \
      XDG_RUNTIME_DIR="$tmp/rt-agent" WAYLAND_DISPLAY=wayland-1 > "$tmp/out9" 2>&1 ||
    fail "shim exited nonzero (test 9)"
  log_lacks '^qt ' "$tmp/log9" "a display-less terminal must not get a Qt prompt on the agent's display"
  log_has "^OPTION ttyname=$bare_tty\$" "$tmp/log9" "display-less terminal should keep its own tty"
  echo "ok 9 - display-less terminal stays on its tty"

  # --- test 10: empty GPG_TTY prefers the active tmux client over Qt ---------
  : > "$tmp/log10a"
  printf 'OPTION grab\nGETPIN\nBYE\n' |
    stub_run "$tmp/log10a" \
      STUB_CLIENTS="$(printf '%s\n' \
        '/dev/pts/46 desktop-session 1000' \
        '/dev/pts/47 remote-session 2000')" \
      XDG_RUNTIME_DIR="$tmp/rt-agent" WAYLAND_DISPLAY=wayland-1 > "$tmp/out10a" 2>&1 ||
    fail "shim exited nonzero (test 10a)"
  log_lacks '^qt ' "$tmp/log10a" "empty GPG_TTY with an attached tmux client must not open Qt on the agent display"
  log_has '^popup-client=/dev/pts/47$' "$tmp/log10a" "empty GPG_TTY did not route to the most recently active tmux client"
  log_has '^OPTION ttyname=/dev/pts/99$' "$tmp/log10a" "empty GPG_TTY did not inject OPTION ttyname for pinentry-curses"
  [ "$(wc -l < "$tmp/out10a")" -eq 4 ] || fail "test 10a Assuan reply count drifted (expected 4: greeting + OPTION grab + GETPIN + BYE)"
  echo "ok 10a - empty GPG_TTY routes to the active tmux client and injects OPTION ttyname"

  # --- test 11: empty GPG_TTY with no tmux client falls back to remote Qt ----
  : > "$tmp/log10b"
  printf 'GETPIN\nBYE\n' |
    stub_run "$tmp/log10b" STUB_NO_CLIENTS=1 \
      PINENTRY_REMOTE_RUNTIME_DIR="$tmp/rt-requester" \
      XDG_RUNTIME_DIR="$tmp/nonexistent" WAYLAND_DISPLAY="" DISPLAY="" > "$tmp/out10b" 2>&1 ||
    fail "shim exited nonzero (test 10b)"
  log_has "^qt runtime=$tmp/rt-requester wayland=wayland-1\$" "$tmp/log10b" \
    "empty GPG_TTY with no tmux client did not fall back to the remote Wayland display"
  echo "ok 10b - empty GPG_TTY with no tmux client falls back to remote Wayland Qt"
else
  echo "skip 8-10b - display tests need script and python3"
fi

# --- test 10 (integration): real tmux server + scripted attached client -----
if ! command -v tmux > /dev/null || ! command -v script > /dev/null; then
  echo "skip 10-11 - integration tests need tmux and script"
  exit 0
fi

mkdir -p "$test_sock"
tmux_test new-session -d -s pinentry-test ||
  fail "could not start test tmux server on $test_sock"
pane_tty="$(tmux_test list-panes -t pinentry-test -F '#{pane_tty}')"
[ -n "$pane_tty" ] || fail "could not resolve test pane tty"

# Hold a writer open on stdin so `script` keeps the attached client alive.
mkfifo "$tmp/client.in"
exec 7<> "$tmp/client.in"
TERM=xterm-256color script -qec "env -u TMUX TMUX_TMPDIR=$test_sock tmux attach -t pinentry-test" \
  /dev/null < "$tmp/client.in" > "$tmp/client.out" 2>&1 &

for _ in $(seq 1 50); do
  tmux_test list-clients 2> /dev/null | grep -q . && break
  sleep 0.1
done
tmux_test list-clients 2> /dev/null | grep -q . || fail "scripted tmux client did not attach"

: > "$tmp/log10"
printf 'OPTION ttyname=%s\nBYE\n' "$pane_tty" |
  env -u TMUX -u GPG_TTY -u WAYLAND_DISPLAY -u DISPLAY TMUX_TMPDIR="$test_sock" STUB_LOG="$tmp/log10" PATH="$tmp/stubpin:$PATH" "$shim" > "$tmp/out10" 2>&1 ||
  fail "shim exited nonzero (integration, pane)"

rewritten="$(sed -n 's/^OPTION ttyname=//p' "$tmp/log10")"
[ -n "$rewritten" ] || fail "integration: ttyname line was not forwarded"
[ "$rewritten" != "$pane_tty" ] || fail "integration: ttyname was not rewritten"
case "$rewritten" in /dev/pts/*) ;; *) fail "integration: popup tty looks wrong: $rewritten" ;; esac
log_has '^tty-exists$' "$tmp/log10" "integration: rewritten tty is not an open terminal"
log_has '^BYE$' "$tmp/log10" "integration: BYE was not forwarded"
echo "ok 10 - real tmux popup integration, pane tty ($pane_tty -> $rewritten)"

# --- test 11 (integration): unusable tty falls back to the real client ------
: > "$tmp/log11"
printf 'OPTION ttyname=/dev/pts/no-such-tty\nBYE\n' |
  env -u TMUX -u GPG_TTY -u WAYLAND_DISPLAY -u DISPLAY TMUX_TMPDIR="$test_sock" STUB_LOG="$tmp/log11" PATH="$tmp/stubpin:$PATH" "$shim" > "$tmp/out11" 2>&1 ||
  fail "shim exited nonzero (integration, unusable tty)"

rewritten11="$(sed -n 's/^OPTION ttyname=//p' "$tmp/log11")"
[ -n "$rewritten11" ] || fail "integration: ttyname line was not forwarded for the unusable tty"
[ "$rewritten11" != "/dev/pts/no-such-tty" ] || fail "integration: unusable ttyname was not rewritten"
case "$rewritten11" in /dev/pts/*) ;; *) fail "integration: popup tty looks wrong: $rewritten11" ;; esac
log_has '^tty-exists$' "$tmp/log11" "integration: rewritten tty is not an open terminal"
echo "ok 11 - real tmux popup integration, unusable tty ($rewritten11)"
