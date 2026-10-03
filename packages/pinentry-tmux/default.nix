{ writeShellApplication
, coreutils
, tmux
, pinentry-curses
}:

# The caller should pass tmux matching the persistent server's version (see
# CUSTOM.programs.tmux.server.package): a tmux client of another version can
# refuse to talk to the running server.
writeShellApplication {
  name = "pinentry";
  runtimeInputs = [ coreutils tmux pinentry-curses ];

  # SC2016: the popup command is single-quoted on purpose; tmux expands it.
  excludeShellChecks = [ "SC2016" ];

  text = builtins.readFile ./pinentry.sh;
}
