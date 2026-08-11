package version

import "testing"

func TestCompareOrdering(t *testing.T) {
	cases := []struct {
		a, b string
		want int
	}{
		// Equality, including "v" prefixes and differing depth.
		{"0.4.9", "0.4.9", 0},
		{"v0.4.9", "0.4.9", 0},
		{"1.2", "1.2.0", 0},
		{"1.2.0.0", "1.2", 0},
		// Ordinary precedence.
		{"0.5.0", "0.4.9", 1},
		{"0.4.9", "0.5.0", -1},
		{"1.0.0", "0.9.9", 1},
		{"0.4.10", "0.4.9", 1}, // numeric, not lexicographic
		{"0.4.9.1", "0.4.9", 1},
		// A release outranks its own pre-releases.
		{"1.0.0", "1.0.0-rc.1", 1},
		{"1.0.0-rc.1", "1.0.0", -1},
		{"1.0.0-rc.2", "1.0.0-rc.1", 1},
		{"1.0.0-beta", "1.0.0-alpha", 1},
		{"1.0.0-rc.1", "1.0.0-rc.1", 0},
		// A pre-release of a higher version still outranks a lower release.
		{"1.1.0-rc.1", "1.0.0", 1},
		// Numeric pre-release fields outrank textual ones.
		{"1.0.0-1", "1.0.0-alpha", 1},
		// Build metadata is ignored.
		{"1.2.3+abc", "1.2.3", 0},
	}

	for _, c := range cases {
		if got := Compare(c.a, c.b); got != c.want {
			t.Errorf("Compare(%q, %q) = %d, want %d", c.a, c.b, got, c.want)
		}
		// Comparison must be antisymmetric.
		if got := Compare(c.b, c.a); got != -c.want {
			t.Errorf("Compare(%q, %q) = %d, want %d (antisymmetry)", c.b, c.a, got, -c.want)
		}
	}
}

func TestIsNewer(t *testing.T) {
	if !IsNewer("0.5.0", "0.4.9") {
		t.Error("0.5.0 should be newer than 0.4.9")
	}
	if IsNewer("0.4.9", "0.4.9") {
		t.Error("an identical version must not report as newer")
	}
	if IsNewer("0.4.8", "0.4.9") {
		t.Error("an older version must not report as newer")
	}
	// A pre-release of the running version must not trigger an update prompt.
	if IsNewer("0.4.9-rc.1", "0.4.9") {
		t.Error("a pre-release must not be newer than its release")
	}
}

func TestCompareToleratesGarbage(t *testing.T) {
	// Malformed upstream input must not panic, and must not be reported as an
	// available update over a well-formed current version.
	for _, bad := range []string{"", "   ", "latest", "v", "..", "abc.def"} {
		if Compare(bad, "0.4.9") > 0 {
			t.Errorf("garbage version %q must not outrank 0.4.9", bad)
		}
	}
}

func TestPlatformIdentifierShape(t *testing.T) {
	// Must match the agent's asset naming so one manifest can serve both.
	got := Platform()
	if got == "" {
		t.Fatal("Platform() must not be empty")
	}
	for _, bad := range []string{"amd64", "arm64", "darwin"} {
		if contains(got, bad) {
			t.Errorf("Platform() = %q, must not contain Go's %q spelling", got, bad)
		}
	}
}

func contains(s, sub string) bool {
	return len(sub) > 0 && len(s) >= len(sub) && indexOf(s, sub) >= 0
}

func indexOf(s, sub string) int {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return i
		}
	}
	return -1
}
