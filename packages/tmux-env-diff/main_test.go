package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writeTemp(t *testing.T, content string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "env")
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestParseEnv(t *testing.T) {
	path := writeTemp(t, "export DISPLAY=:0\nunset XAUTHORITY\nPLAIN=1\n# comment\n")
	env, err := parseEnv(path)
	if err != nil {
		t.Fatal(err)
	}
	if env["DISPLAY"] != ":0" {
		t.Errorf("DISPLAY = %q, want :0", env["DISPLAY"])
	}
	if env["PLAIN"] != "1" {
		t.Errorf("PLAIN = %q, want 1", env["PLAIN"])
	}
	if _, ok := env["XAUTHORITY"]; ok {
		t.Error("unset XAUTHORITY was kept")
	}
}

func TestRender(t *testing.T) {
	current := map[string]string{"DISPLAY": ":0", "WAYLAND_DISPLAY": "wayland-1"}
	target := map[string]string{"DISPLAY": ":2", "WAYLAND_DISPLAY": "wayland-1", "XAUTHORITY": "/tmp/x"}

	out := render(current, target, false, "current", "target")
	for _, want := range []string{
		"--- current",
		"+++ target",
		"-DISPLAY=:0",
		"+DISPLAY=:2",
		"  WAYLAND_DISPLAY=wayland-1",
		"+XAUTHORITY=/tmp/x",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("output missing %q:\n%s", want, out)
		}
	}
	if strings.Contains(out, "(no differences)") {
		t.Errorf("differences not reported:\n%s", out)
	}

	if got := render(current, current, false, "a", "b"); !strings.Contains(got, "(no differences)") {
		t.Errorf("identical environments not reported:\n%s", got)
	}
}
