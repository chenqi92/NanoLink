package handler

import "testing"

func TestParseShellCD(t *testing.T) {
	tests := []struct {
		command string
		want    string
		ok      bool
	}{
		{command: "cd", want: "/", ok: true},
		{command: "cd /data", want: "/data", ok: true},
		{command: "cd logs", want: "logs", ok: true},
		{command: "cd ../logs", want: "../logs", ok: true},
		{command: "cd /data; id", ok: false},
		{command: "cd /data && id", ok: false},
		{command: "cd /data extra", ok: false},
		{command: "echo cd /data", ok: false},
	}

	for _, tt := range tests {
		t.Run(tt.command, func(t *testing.T) {
			got, ok := parseShellCD(tt.command)
			if ok != tt.ok || got != tt.want {
				t.Fatalf("parseShellCD(%q) = (%q, %v), want (%q, %v)", tt.command, got, ok, tt.want, tt.ok)
			}
		})
	}
}
