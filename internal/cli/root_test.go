package cli

import (
	"bytes"
	"strings"
	"testing"
)

// Phase 0 smoke test: the root command tree wires up without panic and
// the `version` subcommand renders the injected BuildInfo.
func TestRootCommandTree(t *testing.T) {
	root := NewRootCommand(BuildInfo{
		Version: "0.0.0-test",
		Commit:  "deadbeef",
		Date:    "1970-01-01",
	})

	wantSubs := []string{"version", "doctor", "run", "status", "report", "uninstall"}
	got := map[string]bool{}
	for _, c := range root.Commands() {
		got[c.Name()] = true
	}
	for _, name := range wantSubs {
		if !got[name] {
			t.Errorf("missing subcommand: %s", name)
		}
	}
}

func TestVersionCommandOutput(t *testing.T) {
	root := NewRootCommand(BuildInfo{
		Version: "0.0.0-test",
		Commit:  "deadbeef",
		Date:    "1970-01-01",
	})

	var out bytes.Buffer
	root.SetOut(&out)
	root.SetArgs([]string{"version"})
	if err := root.Execute(); err != nil {
		t.Fatalf("version command failed: %v", err)
	}

	got := out.String()
	for _, want := range []string{"0.0.0-test", "deadbeef", "1970-01-01"} {
		if !strings.Contains(got, want) {
			t.Errorf("version output missing %q; got %q", want, got)
		}
	}
}
