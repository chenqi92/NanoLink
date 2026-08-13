package handler

import (
	"archive/tar"
	"compress/gzip"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"mime/multipart"
	"os"
	"path"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/chenqi92/NanoLink/apps/server/internal/database"
	"github.com/gin-gonic/gin"
)

var errDeploymentUploadTooLarge = errors.New("deployment upload exceeds the configured limit")

type storedDeploymentUpload struct {
	name          string
	path          string
	size          int64
	sha256        string
	extract       bool
	stripTopLevel bool
}

func (h *DeploymentHandler) storeDeploymentUpload(c *gin.Context, project database.DeploymentProject, projectDir, id string) (storedDeploymentUpload, error) {
	kind := strings.ToLower(strings.TrimSpace(c.PostForm("uploadKind")))
	if kind == "" {
		kind = "artifact"
	}
	extract := project.Type == database.DeploymentProjectStatic
	if raw := strings.TrimSpace(c.PostForm("extract")); raw != "" {
		value, err := strconv.ParseBool(raw)
		if err != nil {
			return storedDeploymentUpload{}, errors.New("extract must be true or false")
		}
		extract = value
	}
	stripTopLevel, err := strconv.ParseBool(defaultString(c.PostForm("stripTopLevel"), "false"))
	if err != nil {
		return storedDeploymentUpload{}, errors.New("stripTopLevel must be true or false")
	}
	if project.Type == database.DeploymentProjectJava && (kind != "artifact" || extract || stripTopLevel) {
		return storedDeploymentUpload{}, errors.New("Java releases must publish one JAR without extraction")
	}
	if kind == "directory" {
		if project.Type != database.DeploymentProjectStatic {
			return storedDeploymentUpload{}, errors.New("directory upload is only available for static projects")
		}
		if !extract {
			return storedDeploymentUpload{}, errors.New("directory uploads must be extracted on the agent")
		}
		return h.storeDeploymentDirectory(c, projectDir, id)
	}
	if kind != "artifact" {
		return storedDeploymentUpload{}, errors.New("uploadKind must be artifact or directory")
	}
	fileHeader, err := c.FormFile("artifact")
	if err != nil {
		return storedDeploymentUpload{}, errors.New("artifact file is required")
	}
	if fileHeader.Size <= 0 || fileHeader.Size > h.maxArtifact {
		return storedDeploymentUpload{}, fmt.Errorf("%w: artifact must be between 1 byte and %d bytes", errDeploymentUploadTooLarge, h.maxArtifact)
	}
	artifactName := filepath.Base(fileHeader.Filename)
	suffix, err := deploymentArtifactSuffix(project.Type, artifactName)
	if err != nil {
		return storedDeploymentUpload{}, err
	}
	if stripTopLevel && (!extract || project.Type != database.DeploymentProjectStatic) {
		return storedDeploymentUpload{}, errors.New("stripTopLevel requires an extracted static archive")
	}
	finalPath := filepath.Join(projectDir, id+suffix)
	size, digest, err := storeDeploymentFile(fileHeader, finalPath, h.maxArtifact)
	if err != nil {
		return storedDeploymentUpload{}, err
	}
	return storedDeploymentUpload{name: artifactName, path: finalPath, size: size, sha256: digest, extract: extract, stripTopLevel: stripTopLevel}, nil
}

func storeDeploymentFile(fileHeader *multipart.FileHeader, finalPath string, max int64) (int64, string, error) {
	in, err := fileHeader.Open()
	if err != nil {
		return 0, "", errors.New("failed to read artifact")
	}
	defer in.Close()
	tmpPath := finalPath + ".upload"
	out, err := os.OpenFile(tmpPath, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o640)
	if err != nil {
		return 0, "", errors.New("failed to create artifact")
	}
	hash := sha256.New()
	written, copyErr := io.Copy(io.MultiWriter(out, hash), io.LimitReader(in, max+1))
	closeErr := out.Close()
	if copyErr != nil || closeErr != nil || written <= 0 || written > max {
		_ = os.Remove(tmpPath)
		return 0, "", fmt.Errorf("%w: artifact could not be stored", errDeploymentUploadTooLarge)
	}
	if err := os.Rename(tmpPath, finalPath); err != nil {
		_ = os.Remove(tmpPath)
		return 0, "", errors.New("failed to finalize artifact")
	}
	return written, hex.EncodeToString(hash.Sum(nil)), nil
}

func (h *DeploymentHandler) storeDeploymentDirectory(c *gin.Context, projectDir, id string) (storedDeploymentUpload, error) {
	form, err := c.MultipartForm()
	if err != nil {
		return storedDeploymentUpload{}, errors.New("failed to parse directory upload")
	}
	defer form.RemoveAll()
	files := form.File["files"]
	paths := form.Value["paths"]
	if len(files) == 0 || len(files) != len(paths) || len(files) > 20_000 {
		return storedDeploymentUpload{}, errors.New("directory upload requires matching files and relative paths")
	}
	normalized, err := normalizeDeploymentDirectoryPaths(paths)
	if err != nil {
		return storedDeploymentUpload{}, err
	}
	var inputSize int64
	for _, file := range files {
		if file.Size < 0 || inputSize > h.maxArtifact-file.Size {
			return storedDeploymentUpload{}, errDeploymentUploadTooLarge
		}
		inputSize += file.Size
	}
	if inputSize <= 0 {
		return storedDeploymentUpload{}, errors.New("directory upload is empty")
	}
	finalPath := filepath.Join(projectDir, id+".tar.gz")
	tmpPath := finalPath + ".upload"
	output, err := os.OpenFile(tmpPath, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o640)
	if err != nil {
		return storedDeploymentUpload{}, errors.New("failed to create directory artifact")
	}
	hash := sha256.New()
	limited := &deploymentLimitWriter{writer: io.MultiWriter(output, hash), remaining: h.maxArtifact}
	gzipWriter := gzip.NewWriter(limited)
	tarWriter := tar.NewWriter(gzipWriter)
	writeErr := writeDeploymentDirectoryTar(tarWriter, files, normalized)
	if closeErr := tarWriter.Close(); writeErr == nil {
		writeErr = closeErr
	}
	if closeErr := gzipWriter.Close(); writeErr == nil {
		writeErr = closeErr
	}
	if closeErr := output.Close(); writeErr == nil {
		writeErr = closeErr
	}
	if writeErr != nil || limited.written <= 0 || limited.written > h.maxArtifact {
		_ = os.Remove(tmpPath)
		if errors.Is(writeErr, errDeploymentUploadTooLarge) {
			return storedDeploymentUpload{}, errDeploymentUploadTooLarge
		}
		return storedDeploymentUpload{}, errors.New("failed to package directory upload")
	}
	if err := os.Rename(tmpPath, finalPath); err != nil {
		_ = os.Remove(tmpPath)
		return storedDeploymentUpload{}, errors.New("failed to finalize directory artifact")
	}
	return storedDeploymentUpload{name: "dist.tar.gz", path: finalPath, size: limited.written, sha256: hex.EncodeToString(hash.Sum(nil)), extract: true}, nil
}

func writeDeploymentDirectoryTar(writer *tar.Writer, files []*multipart.FileHeader, names []string) error {
	for index, fileHeader := range files {
		header := &tar.Header{Name: names[index], Mode: 0o644, Size: fileHeader.Size, Typeflag: tar.TypeReg}
		if err := writer.WriteHeader(header); err != nil {
			return err
		}
		input, err := fileHeader.Open()
		if err != nil {
			return err
		}
		written, copyErr := io.Copy(writer, input)
		closeErr := input.Close()
		if copyErr != nil || closeErr != nil || written != fileHeader.Size {
			return errors.New("directory file changed while it was uploaded")
		}
	}
	return nil
}

func normalizeDeploymentDirectoryPaths(raw []string) ([]string, error) {
	result := make([]string, len(raw))
	seen := make(map[string]bool, len(raw))
	root := ""
	for index, value := range raw {
		if strings.Contains(value, "\\") || strings.ContainsRune(value, '\x00') {
			return nil, errors.New("directory contains an invalid relative path")
		}
		clean := path.Clean(strings.TrimSpace(value))
		parts := strings.Split(clean, "/")
		if clean == "." || strings.HasPrefix(clean, "/") || len(parts) < 2 || parts[0] == ".." {
			return nil, errors.New("directory paths must include one selected root directory")
		}
		if root == "" {
			root = parts[0]
		} else if parts[0] != root {
			return nil, errors.New("directory paths do not share one selected root")
		}
		relative := strings.Join(parts[1:], "/")
		if relative == "" || strings.HasPrefix(relative, "../") || seen[relative] {
			return nil, errors.New("directory contains an invalid or duplicate path")
		}
		seen[relative] = true
		result[index] = relative
	}
	return result, nil
}

type deploymentLimitWriter struct {
	writer    io.Writer
	remaining int64
	written   int64
}

func (w *deploymentLimitWriter) Write(data []byte) (int, error) {
	if int64(len(data)) > w.remaining {
		return 0, errDeploymentUploadTooLarge
	}
	written, err := w.writer.Write(data)
	w.remaining -= int64(written)
	w.written += int64(written)
	return written, err
}

func defaultString(value, fallback string) string {
	if strings.TrimSpace(value) == "" {
		return fallback
	}
	return strings.TrimSpace(value)
}
