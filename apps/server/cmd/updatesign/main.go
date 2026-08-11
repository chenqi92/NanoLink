// Command updatesign generates the Ed25519 release keypair and signs server
// binaries for the self-update channel.
//
// The private key never leaves the release pipeline (store it as a CI secret);
// the public key is what operators put in update.public_key. Because the server
// verifies a detached signature over the exact bytes it downloads, an attacker
// who takes over the release origin still cannot produce an installable build.
//
// Usage:
//
//	updatesign keygen
//	    Print a fresh keypair. Store the private key as a CI secret and publish
//	    the public key in documentation and default config.
//
//	updatesign sign -key <hex|@file|env:NAME> <file>...
//	    Write "<file>.sig" next to each input, containing the hex signature.
//
//	updatesign verify -pub <hex> <file>...
//	    Check each "<file>.sig" against the public key. Run this in CI after
//	    signing so a broken key never reaches a release.
//
//	updatesign manifest -version <v> [-changelog <text>] [-min-version <v>] \
//	    -pub <hex> -dir <dir> [-out version.json]
//	    Build the version.json consumed by update.source=custom, from the signed
//	    binaries present in -dir.
package main

import (
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}

	var err error
	switch os.Args[1] {
	case "keygen":
		err = keygen()
	case "sign":
		err = sign(os.Args[2:])
	case "verify":
		err = verify(os.Args[2:])
	case "manifest":
		err = manifest(os.Args[2:])
	case "-h", "--help", "help":
		usage()
		return
	default:
		err = fmt.Errorf("unknown subcommand %q", os.Args[1])
	}

	if err != nil {
		fmt.Fprintf(os.Stderr, "updatesign: %v\n", err)
		os.Exit(1)
	}
}

func usage() {
	fmt.Fprint(os.Stderr, `updatesign - release signing for the NanoOps server self-update channel

  updatesign keygen
  updatesign sign     -key <hex|@file|env:NAME> <file>...
  updatesign verify   -pub <hex> <file>...
  updatesign manifest -version <v> -pub <hex> -dir <dir> [-out version.json]
                      [-changelog <text>] [-min-version <v>]
`)
}

func keygen() error {
	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		return err
	}
	// Printed rather than written to disk so the private key does not linger in
	// a CI workspace that later gets archived.
	fmt.Printf("private key (keep secret, store as a CI secret):\n%s\n\n", hex.EncodeToString(priv.Seed()))
	fmt.Printf("public key (publish; set as update.public_key):\n%s\n", hex.EncodeToString(pub))
	return nil
}

func sign(args []string) error {
	fs := flag.NewFlagSet("sign", flag.ExitOnError)
	keyRef := fs.String("key", "", "private key: hex seed, @file, or env:NAME")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if fs.NArg() == 0 {
		return errors.New("sign: no files given")
	}

	priv, err := loadPrivateKey(*keyRef)
	if err != nil {
		return err
	}

	for _, path := range fs.Args() {
		data, err := os.ReadFile(path)
		if err != nil {
			return fmt.Errorf("read %s: %w", path, err)
		}
		sigPath := path + ".sig"
		sig := hex.EncodeToString(ed25519.Sign(priv, data))
		if err := os.WriteFile(sigPath, []byte(sig+"\n"), 0o644); err != nil {
			return fmt.Errorf("write %s: %w", sigPath, err)
		}
		fmt.Printf("signed %s -> %s\n", filepath.Base(path), filepath.Base(sigPath))
	}
	return nil
}

func verify(args []string) error {
	fs := flag.NewFlagSet("verify", flag.ExitOnError)
	pubHex := fs.String("pub", "", "public key, hex")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if fs.NArg() == 0 {
		return errors.New("verify: no files given")
	}

	pub, err := decodeKey(*pubHex, ed25519.PublicKeySize, "public key")
	if err != nil {
		return err
	}

	for _, path := range fs.Args() {
		data, err := os.ReadFile(path)
		if err != nil {
			return fmt.Errorf("read %s: %w", path, err)
		}
		rawSig, err := os.ReadFile(path + ".sig")
		if err != nil {
			return fmt.Errorf("read %s.sig: %w", path, err)
		}
		fields := strings.Fields(string(rawSig))
		if len(fields) == 0 {
			return fmt.Errorf("%s.sig is empty", path)
		}
		sig, err := hex.DecodeString(fields[0])
		if err != nil {
			return fmt.Errorf("%s.sig is not hex: %w", path, err)
		}
		if !ed25519.Verify(ed25519.PublicKey(pub), data, sig) {
			return fmt.Errorf("%s: signature does not verify against the given public key", path)
		}
		fmt.Printf("verified %s\n", filepath.Base(path))
	}
	return nil
}

// releaseManifest mirrors service.ReleaseManifest. It is duplicated rather than
// imported so this tool stays a standalone binary with no server dependencies.
type releaseManifest struct {
	Version     string            `json:"version"`
	ReleaseDate string            `json:"releaseDate"`
	Changelog   string            `json:"changelog,omitempty"`
	MinVersion  string            `json:"minVersion,omitempty"`
	Assets      map[string]string `json:"assets"`
	Checksums   map[string]string `json:"checksums"`
	Signatures  map[string]string `json:"signatures"`
}

func manifest(args []string) error {
	fs := flag.NewFlagSet("manifest", flag.ExitOnError)
	ver := fs.String("version", "", "release version, e.g. 0.5.0")
	changelog := fs.String("changelog", "", "release notes")
	minVersion := fs.String("min-version", "", "oldest version that may upgrade directly to this one")
	pubHex := fs.String("pub", "", "public key, hex; signatures are verified before being written")
	dir := fs.String("dir", ".", "directory holding nanolink-server-<platform> binaries and .sig files")
	out := fs.String("out", "version.json", "output path")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if strings.TrimSpace(*ver) == "" {
		return errors.New("manifest: -version is required")
	}

	pub, err := decodeKey(*pubHex, ed25519.PublicKeySize, "public key")
	if err != nil {
		return err
	}

	entries, err := os.ReadDir(*dir)
	if err != nil {
		return fmt.Errorf("read %s: %w", *dir, err)
	}

	m := releaseManifest{
		Version:     strings.TrimPrefix(strings.TrimSpace(*ver), "v"),
		ReleaseDate: time.Now().UTC().Format(time.RFC3339),
		Changelog:   *changelog,
		MinVersion:  strings.TrimPrefix(strings.TrimSpace(*minVersion), "v"),
		Assets:      map[string]string{},
		Checksums:   map[string]string{},
		Signatures:  map[string]string{},
	}

	const stem = "nanolink-server-"
	for _, e := range entries {
		name := e.Name()
		if e.IsDir() || !strings.HasPrefix(name, stem) || strings.HasSuffix(name, ".sig") {
			continue
		}
		platform := strings.TrimSuffix(strings.TrimPrefix(name, stem), ".exe")

		data, err := os.ReadFile(filepath.Join(*dir, name))
		if err != nil {
			return fmt.Errorf("read %s: %w", name, err)
		}
		rawSig, err := os.ReadFile(filepath.Join(*dir, name+".sig"))
		if err != nil {
			return fmt.Errorf("%s has no signature; run `updatesign sign` first: %w", name, err)
		}
		fields := strings.Fields(string(rawSig))
		if len(fields) == 0 {
			return fmt.Errorf("%s.sig is empty", name)
		}
		sigBytes, err := hex.DecodeString(fields[0])
		if err != nil {
			return fmt.Errorf("%s.sig is not hex: %w", name, err)
		}
		// Verify before publishing: a manifest that advertises a signature the
		// server will reject turns every client into a failed update.
		if !ed25519.Verify(ed25519.PublicKey(pub), data, sigBytes) {
			return fmt.Errorf("%s: signature does not verify against the given public key", name)
		}

		sum := sha256.Sum256(data)
		m.Assets[platform] = name
		m.Checksums[platform] = hex.EncodeToString(sum[:])
		m.Signatures[platform] = fields[0]
	}

	if len(m.Assets) == 0 {
		return fmt.Errorf("no %s* binaries found in %s", stem, *dir)
	}

	body, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return err
	}
	if err := os.WriteFile(*out, append(body, '\n'), 0o644); err != nil {
		return fmt.Errorf("write %s: %w", *out, err)
	}
	fmt.Printf("wrote %s with %d platform(s)\n", *out, len(m.Assets))
	return nil
}

// loadPrivateKey reads a 32-byte Ed25519 seed from a hex literal, a file
// (@path), or an environment variable (env:NAME). env: is what CI should use, so
// the key never appears in a process argument list.
func loadPrivateKey(ref string) (ed25519.PrivateKey, error) {
	raw := strings.TrimSpace(ref)
	switch {
	case raw == "":
		return nil, errors.New("sign: -key is required")
	case strings.HasPrefix(raw, "env:"):
		name := strings.TrimPrefix(raw, "env:")
		val := strings.TrimSpace(os.Getenv(name))
		if val == "" {
			return nil, fmt.Errorf("environment variable %s is empty", name)
		}
		raw = val
	case strings.HasPrefix(raw, "@"):
		data, err := os.ReadFile(strings.TrimPrefix(raw, "@"))
		if err != nil {
			return nil, fmt.Errorf("read key file: %w", err)
		}
		raw = strings.TrimSpace(string(data))
	}

	seed, err := hex.DecodeString(raw)
	if err != nil {
		return nil, fmt.Errorf("private key is not hex: %w", err)
	}
	switch len(seed) {
	case ed25519.SeedSize:
		return ed25519.NewKeyFromSeed(seed), nil
	case ed25519.PrivateKeySize:
		// Accept a full expanded key too, since keygen output can be copied either way.
		return ed25519.PrivateKey(seed), nil
	default:
		return nil, fmt.Errorf("private key must be %d or %d bytes, got %d",
			ed25519.SeedSize, ed25519.PrivateKeySize, len(seed))
	}
}

func decodeKey(value string, size int, label string) ([]byte, error) {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return nil, fmt.Errorf("%s is required", label)
	}
	key, err := hex.DecodeString(trimmed)
	if err != nil {
		return nil, fmt.Errorf("%s is not hex: %w", label, err)
	}
	if len(key) != size {
		return nil, fmt.Errorf("%s must be %d bytes, got %d", label, size, len(key))
	}
	return key, nil
}
