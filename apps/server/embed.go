package server

import "embed"

// WebFS contains the embedded web dashboard files
//
//go:embed web/dist/*
var WebFS embed.FS
