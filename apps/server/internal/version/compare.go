package version

import (
	"strconv"
	"strings"
)

// Compare returns a positive number when a is newer than b, a negative number
// when a is older, and 0 when they are equivalent.
//
// The ordering deliberately mirrors the agent's is_newer_version
// (agent/src/executor/update.rs) so the server and the agent never disagree
// about which of two releases is newer:
//   - an optional leading "v" is ignored
//   - arbitrary numeric depth is supported (1.2 == 1.2.0, 1.2.3.4 is valid)
//   - missing trailing components count as 0
//   - a release outranks any of its pre-releases (1.0.0 > 1.0.0-rc.1)
//   - pre-release identifiers compare field by field, numeric before textual
func Compare(a, b string) int {
	aCore, aPre := splitPrerelease(a)
	bCore, bPre := splitPrerelease(b)

	aNums, bNums := numericFields(aCore), numericFields(bCore)
	depth := max(len(aNums), len(bNums))
	for i := range depth {
		if d := fieldAt(aNums, i) - fieldAt(bNums, i); d != 0 {
			return sign(d)
		}
	}

	switch {
	case aPre == "" && bPre == "":
		return 0
	case aPre == "":
		return 1 // 1.0.0 > 1.0.0-rc.1
	case bPre == "":
		return -1 // 1.0.0-rc.1 < 1.0.0
	default:
		return comparePrerelease(aPre, bPre)
	}
}

// IsNewer reports whether latest is strictly newer than current.
func IsNewer(latest, current string) bool {
	return Compare(latest, current) > 0
}

// splitPrerelease trims a "v" prefix and separates "1.2.3-rc.1" into its core
// and pre-release halves. Build metadata ("+abc") is ignored, per SemVer.
func splitPrerelease(v string) (core, pre string) {
	v = strings.TrimSpace(v)
	v = strings.TrimPrefix(strings.TrimPrefix(v, "v"), "V")
	if plus := strings.IndexByte(v, '+'); plus >= 0 {
		v = v[:plus]
	}
	if dash := strings.IndexByte(v, '-'); dash >= 0 {
		return v[:dash], v[dash+1:]
	}
	return v, ""
}

// numericFields parses the dot-separated numeric components of a core version.
// Non-numeric components are skipped rather than failing the whole comparison,
// matching the agent's filter_map behaviour.
func numericFields(core string) []int64 {
	if core == "" {
		return nil
	}
	parts := strings.Split(core, ".")
	out := make([]int64, 0, len(parts))
	for _, p := range parts {
		if n, err := strconv.ParseInt(strings.TrimSpace(p), 10, 64); err == nil {
			out = append(out, n)
		}
	}
	return out
}

// comparePrerelease orders two pre-release suffixes field by field. A numeric
// field outranks a textual one; textual fields compare lexicographically.
func comparePrerelease(a, b string) int {
	aParts, bParts := strings.Split(a, "."), strings.Split(b, ".")
	for i := range max(len(aParts), len(bParts)) {
		ap, bp := partAt(aParts, i), partAt(bParts, i)
		an, aErr := strconv.ParseInt(ap, 10, 64)
		bn, bErr := strconv.ParseInt(bp, 10, 64)
		switch {
		case aErr == nil && bErr == nil:
			if an != bn {
				return sign(an - bn)
			}
		case aErr == nil:
			return 1 // numeric > textual
		case bErr == nil:
			return -1 // textual < numeric
		default:
			if c := strings.Compare(ap, bp); c != 0 {
				return c
			}
		}
	}
	return 0
}

func fieldAt(fields []int64, i int) int64 {
	if i < len(fields) {
		return fields[i]
	}
	return 0
}

func partAt(parts []string, i int) string {
	if i < len(parts) {
		return strings.TrimSpace(parts[i])
	}
	return ""
}

func sign(d int64) int {
	if d > 0 {
		return 1
	}
	if d < 0 {
		return -1
	}
	return 0
}
