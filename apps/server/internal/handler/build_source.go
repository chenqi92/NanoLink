package handler

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/netip"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
)

func (h *BuildHandler) fetchRemoteSource(pipelineID uint, rawURL string) (string, string, int64, string, error) {
	parsed, err := parsePublicSourceURL(rawURL)
	if err != nil {
		return "", "", 0, "", err
	}
	name := filepath.Base(parsed.Path)
	if err := validateBuildArchiveName(name); err != nil {
		return "", "", 0, "", err
	}
	client := sourceHTTPClient(h.fetchTimeout, h.allowedSourceHosts)
	request, err := http.NewRequestWithContext(context.Background(), http.MethodGet, parsed.String(), nil)
	if err != nil {
		return "", "", 0, "", err
	}
	request.Header.Set("User-Agent", "NanoOps-BuildFetcher/1")
	response, err := client.Do(request)
	if err != nil {
		return "", "", 0, "", err
	}
	defer response.Body.Close()
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return "", "", 0, "", fmt.Errorf("source returned HTTP %d", response.StatusCode)
	}
	if response.ContentLength > h.maxSource {
		return "", "", 0, "", errors.New("remote source exceeds the configured limit")
	}

	dir := filepath.Join(h.storageRoot, "sources", strconv.FormatUint(uint64(pipelineID), 10))
	if err := os.MkdirAll(dir, 0o750); err != nil {
		return "", "", 0, "", fmt.Errorf("prepare source storage: %w", err)
	}
	finalPath := filepath.Join(dir, uuid.NewString()+buildArchiveSuffix(name))
	tmpPath := finalPath + ".download"
	output, err := os.OpenFile(tmpPath, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o640)
	if err != nil {
		return "", "", 0, "", fmt.Errorf("create source file: %w", err)
	}
	hash := sha256.New()
	written, copyErr := io.Copy(io.MultiWriter(output, hash), io.LimitReader(response.Body, h.maxSource+1))
	closeErr := output.Close()
	if copyErr != nil || closeErr != nil || written <= 0 || written > h.maxSource {
		_ = os.Remove(tmpPath)
		return "", "", 0, "", errors.New("remote source exceeds the configured limit or could not be stored")
	}
	if err := os.Rename(tmpPath, finalPath); err != nil {
		_ = os.Remove(tmpPath)
		return "", "", 0, "", fmt.Errorf("finalize source: %w", err)
	}
	return finalPath, name, written, hex.EncodeToString(hash.Sum(nil)), nil
}

func parsePublicSourceURL(raw string) (*url.URL, error) {
	parsed, err := url.Parse(strings.TrimSpace(raw))
	if err != nil || parsed == nil || parsed.Host == "" || (parsed.Scheme != "http" && parsed.Scheme != "https") || parsed.User != nil {
		return nil, errors.New("source URL must be absolute HTTP(S) without credentials")
	}
	if parsed.Fragment != "" {
		parsed.Fragment = ""
	}
	return parsed, nil
}

func sourceHTTPClient(timeout time.Duration, allowedPrivateHosts map[string]bool) *http.Client {
	dialer := &net.Dialer{Timeout: 15 * time.Second, KeepAlive: 30 * time.Second}
	transport := &http.Transport{
		Proxy: nil,
		DialContext: func(ctx context.Context, network, address string) (net.Conn, error) {
			host, port, err := net.SplitHostPort(address)
			if err != nil {
				return nil, err
			}
			ips, err := net.DefaultResolver.LookupIP(ctx, "ip", host)
			if err != nil {
				return nil, err
			}
			if len(ips) == 0 {
				return nil, errors.New("source host did not resolve")
			}
			var selected net.IP
			allowPrivate := allowedPrivateHosts[strings.ToLower(strings.TrimSuffix(host, "."))]
			for _, ip := range ips {
				if !allowPrivate && !isPublicBuildSourceIP(ip) {
					return nil, fmt.Errorf("source host resolves to a private or reserved address: %s", ip)
				}
				if selected == nil {
					selected = ip
				}
			}
			return dialer.DialContext(ctx, network, net.JoinHostPort(selected.String(), port))
		},
		ForceAttemptHTTP2:     true,
		TLSHandshakeTimeout:   15 * time.Second,
		ResponseHeaderTimeout: 30 * time.Second,
		IdleConnTimeout:       30 * time.Second,
	}
	return &http.Client{
		Transport: transport,
		Timeout:   timeout,
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			if len(via) >= 5 {
				return errors.New("source redirected too many times")
			}
			if _, err := parsePublicSourceURL(req.URL.String()); err != nil {
				return err
			}
			return nil
		},
	}
}

func isPublicBuildSourceIP(ip net.IP) bool {
	if ip == nil || !ip.IsGlobalUnicast() || ip.IsPrivate() || ip.IsLoopback() || ip.IsLinkLocalUnicast() || ip.IsLinkLocalMulticast() || ip.IsUnspecified() {
		return false
	}
	address, ok := netip.AddrFromSlice(ip)
	if !ok {
		return false
	}
	address = address.Unmap()
	for _, prefix := range reservedBuildSourcePrefixes {
		if prefix.Contains(address) {
			return false
		}
	}
	return true
}

var reservedBuildSourcePrefixes = func() []netip.Prefix {
	raw := []string{
		"0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8", "169.254.0.0/16", "172.16.0.0/12",
		"192.0.0.0/24", "192.0.2.0/24", "192.168.0.0/16", "198.18.0.0/15", "198.51.100.0/24", "203.0.113.0/24", "224.0.0.0/4", "240.0.0.0/4",
		"::/128", "::1/128", "100::/64", "2001:db8::/32", "fc00::/7", "fe80::/10", "ff00::/8",
	}
	result := make([]netip.Prefix, 0, len(raw))
	for _, value := range raw {
		result = append(result, netip.MustParsePrefix(value))
	}
	return result
}()
