#!/usr/bin/env bash
# Tests for the pinentry-tmux shim.
#
#   ./test.sh [path/to/pinentry.sh]
#
# Test 1 (stubs): verifies ttyname rewriting, pass-through when the tty is not
# a tmux pane, popup teardown, and the no-client fast path.
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
unset TMUX TMUX_PANE

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

mkdir -p "$tmp/stubtmux" "$tmp/stubpin"

# --- stub tmux -------------------------------------------------------------
cat > "$tmp/stubtmux/tmux" <<'EOF'
#!/usr/bin/env bash
sub="$1"; shift
case "$sub" in
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

# --- test 1: rewrite, teardown --------------------------------------------
: > "$tmp/log1"
printf 'OPTION ttyname=/dev/pts/16\nBYE\n' |
  env -u TMUX STUB_LOG="$tmp/log1" PATH="$tmp/stubtmux:$tmp/stubpin:$PATH" "$shim" > "$tmp/out1" 2>&1 ||
  fail "shim exited nonzero (test 1)"

log_has '^OK stub$' "$tmp/out1" "pinentry greeting was not relayed"
log_has '^OPTION ttyname=/dev/pts/99$' "$tmp/log1" "ttyname was not rewritten to the popup tty"
log_has '^BYE$' "$tmp/log1" "BYE was not forwarded"
log_has '^popup-closed$' "$tmp/log1" "popup was not torn down"
echo "ok 1 - popup ttyname rewrite and teardown"

# --- test 2: non-pane tty passes through unchanged -------------------------
: > "$tmp/log2"
printf 'OPTION ttyname=/dev/pts/46\nBYE\n' |
  env -u TMUX STUB_LOG="$tmp/log2" PATH="$tmp/stubtmux:$tmp/stubpin:$PATH" "$shim" > "$tmp/out2" 2>&1 ||
  fail "shim exited nonzero (test 2)"

log_has '^OPTION ttyname=/dev/pts/46$' "$tmp/log2" "non-pane ttyname should pass through"
if grep -q '^popup-closed$' "$tmp/log2"; then
  fail "popup must not be opened for a non-pane tty"
fi
echo "ok 2 - non-pane tty passes through"

# --- test 3: no attached client execs pinentry directly --------------------
: > "$tmp/log3"
printf 'OPTION ttyname=/dev/pts/16\nBYE\n' |
  env -u TMUX STUB_LOG="$tmp/log3" STUB_NO_CLIENTS=1 PATH="$tmp/stubtmux:$tmp/stubpin:$PATH" "$shim" > "$tmp/out3" 2>&1 ||
  fail "shim exited nonzero (test 3)"

log_has '^OPTION ttyname=/dev/pts/16$' "$tmp/log3" "no-client path must pass commands straight to pinentry"
if grep -q '^popup-closed$' "$tmp/log3"; then
  fail "popup must not be opened without an attached client"
fi
echo "ok 3 - no attached client fast path"

# --- test 4 (integration): real tmux server + scripted attached client -----
if ! command -v tmux > /dev/null || ! command -v script > /dev/null; then
  echo "skip 4 - integration test needs tmux and script"
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
client_pid=$!

for _ in $(seq 1 50); do
  tmux_test list-clients 2> /dev/null | grep -q . && break
  sleep 0.1
done
tmux_test list-clients 2> /dev/null | grep -q . || fail "scripted tmux client did not attach"

: > "$tmp/log4"
printf 'OPTION ttyname=%s\nBYE\n' "$pane_tty" |
  env -u TMUX TMUX_TMPDIR="$test_sock" STUB_LOG="$tmp/log4" PATH="$tmp/stubpin:$PATH" "$shim" > "$tmp/out4" 2>&1 ||
  fail "shim exited nonzero (integration)"

rewritten="$(sed -n 's/^OPTION ttyname=//p' "$tmp/log4")"
[ -n "$rewritten" ] || fail "integration: ttyname line was not forwarded"
[ "$rewritten" != "$pane_tty" ] || fail "integration: ttyname was not rewritten"
case "$rewritten" in /dev/pts/*) ;; *) fail "integration: popup tty looks wrong: $rewritten" ;; esac
log_has '^tty-exists$' "$tmp/log4" "integration: rewritten tty is not an open terminal"
log_has '^BYE$' "$tmp/log4" "integration: BYE was not forwarded"
echo "ok 4 - real tmux popup integration ($pane_tty -> $rewritten)"
