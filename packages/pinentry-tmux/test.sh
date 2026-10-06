#!/usr/bin/env bash
# Tests for the pinentry-tmux shim.
#
#   ./test.sh [path/to/pinentry.sh]
#
# Test 1 (stubs): verifies ttyname rewriting for pane, client, and unusable
# ttys, pass-through for plain terminals, the no-client failure, and popup
# teardown.
# Test 2 (integration): verifies the popup dance against a real isolated tmux
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
    printf '/dev/pts/46 test-session 1000\n'
    ;;
  list-panes)
    printf '%s test-session\n' "${STUB_PANE_TTY:-/dev/pts/16}"
    ;;
  display-popup)
    ttyfifo=""; donefifo=""
    while [ $# -gt 0 ]; do
      case "$1" in
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
      ;;
    BYE*)
      printf 'OK bye\n'
      exit 0
      ;;
  esac
done
EOF
chmod +x "$tmp/stubpin/pinentry-curses"

stub_run() { # <log> <extra env>... -- reads stdin
  local log="$1"; shift
  env -u TMUX STUB_LOG="$log" "$@" PATH="$tmp/stubtmux:$tmp/stubpin:$PATH" "$shim"
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

# --- test 7 (integration): real tmux server + scripted attached client -----
if ! command -v tmux > /dev/null || ! command -v script > /dev/null; then
  echo "skip 7 - integration test needs tmux and script"
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

: > "$tmp/log7"
printf 'OPTION ttyname=%s\nBYE\n' "$pane_tty" |
  env -u TMUX TMUX_TMPDIR="$test_sock" STUB_LOG="$tmp/log7" PATH="$tmp/stubpin:$PATH" "$shim" > "$tmp/out7" 2>&1 ||
  fail "shim exited nonzero (integration, pane)"

rewritten="$(sed -n 's/^OPTION ttyname=//p' "$tmp/log7")"
[ -n "$rewritten" ] || fail "integration: ttyname line was not forwarded"
[ "$rewritten" != "$pane_tty" ] || fail "integration: ttyname was not rewritten"
case "$rewritten" in /dev/pts/*) ;; *) fail "integration: popup tty looks wrong: $rewritten" ;; esac
log_has '^tty-exists$' "$tmp/log7" "integration: rewritten tty is not an open terminal"
log_has '^BYE$' "$tmp/log7" "integration: BYE was not forwarded"
echo "ok 7 - real tmux popup integration, pane tty ($pane_tty -> $rewritten)"

# --- test 8 (integration): unusable tty falls back to the real client ------
: > "$tmp/log8"
printf 'OPTION ttyname=/dev/pts/no-such-tty\nBYE\n' |
  env -u TMUX TMUX_TMPDIR="$test_sock" STUB_LOG="$tmp/log8" PATH="$tmp/stubpin:$PATH" "$shim" > "$tmp/out8" 2>&1 ||
  fail "shim exited nonzero (integration, unusable tty)"

rewritten8="$(sed -n 's/^OPTION ttyname=//p' "$tmp/log8")"
[ -n "$rewritten8" ] || fail "integration: ttyname line was not forwarded for the unusable tty"
[ "$rewritten8" != "/dev/pts/no-such-tty" ] || fail "integration: unusable ttyname was not rewritten"
case "$rewritten8" in /dev/pts/*) ;; *) fail "integration: popup tty looks wrong: $rewritten8" ;; esac
log_has '^tty-exists$' "$tmp/log8" "integration: rewritten tty is not an open terminal"
echo "ok 8 - real tmux popup integration, unusable tty ($rewritten8)"
