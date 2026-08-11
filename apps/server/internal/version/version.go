// Package version exposes the server's build identity and the semantic-version
// comparison used by the self-update checker.
//
// The values below are injected at build time so the running process reports
// the same version the repository tracks in ./VERSION:
//
//	go build -ldflags "-X github.com/chenqi92/NanoLink/apps/server/internal/version.Version=$(cat VERSION)"
//
// The fallback literals keep a plain `go build ./...` (local dev, tests) working
// without any linker flags.
package version

import "runtime"

var (
	// Version is the semantic version of this build, without a leading "v".
	Version = "0.4.9"
	// Commit is the short git SHA this binary was built from.
	Commit = "unknown"
	// BuildTime is the RFC3339 UTC timestamp of the build.
	BuildTime = "unknown"
)

// Info describes the running build. It is returned verbatim by GET /api/version.
//
// GoPlatform and AssetPlatform describe the same machine in two vocabularies:
// Go's own (windows/amd64) and the release pipeline's (windows-x86_64). Both are
// reported because operators read the first and the updater matches the second.
type Info struct {
	Version       string `json:"version"`
	Commit        string `json:"commit"`
	BuildTime     string `json:"buildTime"`
	GoVersion     string `json:"goVersion"`
	GoPlatform    string `json:"goPlatform"`
	AssetPlatform string `json:"assetPlatform"`
}

// Current returns the running build's identity.
func Current() Info {
	return Info{
		Version:       Version,
		Commit:        Commit,
		BuildTime:     BuildTime,
		GoVersion:     runtime.Version(),
		GoPlatform:    runtime.GOOS + "/" + runtime.GOARCH,
		AssetPlatform: Platform(),
	}
}

// Platform returns the release-asset platform identifier for this build, using
// the same naming the agent release pipeline already emits (linux-x86_64,
// macos-aarch64, windows-x86_64) so both can share one manifest layout.
func Platform() string {
	goos, arch := runtime.GOOS, runtime.GOARCH
	switch arch {
	case "amd64":
		arch = "x86_64"
	case "arm64":
		arch = "aarch64"
	}
	if goos == "darwin" {
		goos = "macos"
	}
	return goos + "-" + arch
}
