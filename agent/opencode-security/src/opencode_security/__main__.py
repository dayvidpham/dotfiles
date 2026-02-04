"""Entry point for opencode-security-filter command."""

import sys
import argparse
from .filter import SecurityFilter
from .proxy import SecurityProxy


def main() -> None:
    parser = argparse.ArgumentParser(
        description="OpenCode Security Filter - ACP proxy for file access control"
    )
    parser.add_argument(
        "--version", action="version", version="%(prog)s 0.1.0"
    )
    parser.add_argument(
        "--check", metavar="PATH",
        help="Check a single path and print result (for testing)"
    )
    parser.add_argument(
        "--verbose", "-v", action="store_true",
        help="Enable verbose output"
    )

    args = parser.parse_args()

    filter = SecurityFilter()

    if args.check:
        # Single path check mode (for testing)
        result = filter.check(args.check)
        print(f"Path: {result.file_path}")
        print(f"Canonical: {result.canonical_path}")
        print(f"Decision: {result.decision}")
        print(f"Reason: {result.reason}")
        if result.matched_pattern:
            print(f"Pattern: {result.matched_pattern.pattern}")
            print(f"Level: {result.matched_level.value if result.matched_level else 'N/A'}")
        sys.exit(0 if result.decision != "deny" else 1)

    # Default: run as proxy (stdin/stdout message loop)
    proxy = SecurityProxy(filter)
    try:
        _run_proxy_loop(proxy, verbose=args.verbose)
    except KeyboardInterrupt:
        sys.exit(0)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


def _run_proxy_loop(proxy: SecurityProxy, verbose: bool = False) -> None:
    """Run the proxy message loop on stdin/stdout.

    Reads JSON-RPC messages from stdin, processes them through the security
    proxy, and writes responses to stdout.
    """
    for line in sys.stdin:
        raw = line.encode("utf-8")

        response, should_forward = proxy.process_agent_message(raw)

        if response is not None:
            # Send response back to agent
            sys.stdout.write(response.decode("utf-8"))
            sys.stdout.write("\n")
            sys.stdout.flush()
        elif should_forward:
            # Forward original message unchanged
            sys.stdout.write(line)
            sys.stdout.flush()

        if verbose:
            print(f"[proxy] forwarded={should_forward}, responded={response is not None}",
                  file=sys.stderr)


if __name__ == "__main__":
    main()
