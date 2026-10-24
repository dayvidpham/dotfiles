// tmux-env-diff prints a stable, colourised diff between two environment
// dumps. Only the standard library is used, and the binary is built with
// CGO_ENABLED=0, so it can be copied between machines and executed anywhere.
//
// It understands the snapshot format written by tmux-client-env:
//
//	export DISPLAY=:0
//	export WAYLAND_DISPLAY=wayland-1
//	unset XAUTHORITY
//
// as well as plain VAR=value lines. Variables are compared by name, in sorted
// order, so the output does not depend on the input ordering.
package main

import (
	"bufio"
	"flag"
	"fmt"
	"os"
	"sort"
	"strings"
)

const (
	red   = "\x1b[31m"
	green = "\x1b[32m"
	dim   = "\x1b[2m"
	reset = "\x1b[0m"
)

// parseEnv reads an environment dump into a variable map.
func parseEnv(path string) (map[string]string, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	env := make(map[string]string)
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		line = strings.TrimPrefix(line, "export ")
		if name, ok := strings.CutPrefix(line, "unset "); ok {
			delete(env, strings.TrimSpace(name))
			continue
		}
		name, value, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		env[strings.TrimSpace(name)] = value
	}
	return env, sc.Err()
}

func sortedUnion(current, target map[string]string) []string {
	seen := make(map[string]struct{}, len(current)+len(target))
	keys := make([]string, 0, len(current)+len(target))
	for k := range current {
		seen[k] = struct{}{}
		keys = append(keys, k)
	}
	for k := range target {
		if _, ok := seen[k]; !ok {
			keys = append(keys, k)
		}
	}
	sort.Strings(keys)
	return keys
}

func paint(b *strings.Builder, color bool, code, line string) {
	if color {
		b.WriteString(code)
	}
	b.WriteString(line)
	if color {
		b.WriteString(reset)
	}
	b.WriteByte('\n')
}

// render produces the diff text for two parsed environments.
func render(current, target map[string]string, color bool, currentLabel, targetLabel string) string {
	var b strings.Builder
	paint(&b, color, dim, "--- "+currentLabel)
	paint(&b, color, dim, "+++ "+targetLabel)

	changed := false
	for _, name := range sortedUnion(current, target) {
		currentValue, inCurrent := current[name]
		targetValue, inTarget := target[name]
		switch {
		case inCurrent && inTarget && currentValue == targetValue:
			b.WriteString("  " + name + "=" + currentValue + "\n")
		case inCurrent && inTarget:
			changed = true
			paint(&b, color, red, "-"+name+"="+currentValue)
			paint(&b, color, green, "+"+name+"="+targetValue)
		case inCurrent:
			changed = true
			paint(&b, color, red, "-"+name+"="+currentValue)
		case inTarget:
			changed = true
			paint(&b, color, green, "+"+name+"="+targetValue)
		}
	}
	if !changed {
		paint(&b, color, dim, "(no differences)")
	}
	return b.String()
}

func isTerminal() bool {
	info, err := os.Stdout.Stat()
	if err != nil {
		return false
	}
	return info.Mode()&os.ModeCharDevice != 0
}

func main() {
	colorMode := flag.String("color", "auto", "colourise output: auto, always or never")
	currentLabel := flag.String("current-label", "current", "label for the first environment")
	targetLabel := flag.String("target-label", "target", "label for the second environment")
	flag.Usage = func() {
		fmt.Fprintf(flag.CommandLine.Output(), "usage: %s [flags] CURRENT TARGET\n", os.Args[0])
		flag.PrintDefaults()
	}
	flag.Parse()

	if flag.NArg() != 2 {
		flag.Usage()
		os.Exit(2)
	}

	var color bool
	switch *colorMode {
	case "always":
		color = true
	case "never":
		color = false
	case "auto":
		color = isTerminal()
	default:
		fmt.Fprintf(os.Stderr, "%s: invalid --color %q (want auto, always or never)\n", os.Args[0], *colorMode)
		os.Exit(2)
	}

	current, err := parseEnv(flag.Arg(0))
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s: %v\n", os.Args[0], err)
		os.Exit(1)
	}
	target, err := parseEnv(flag.Arg(1))
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s: %v\n", os.Args[0], err)
		os.Exit(1)
	}

	fmt.Print(render(current, target, color, *currentLabel, *targetLabel))
}
