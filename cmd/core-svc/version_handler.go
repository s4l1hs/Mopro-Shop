package main

import (
	"encoding/json"
	"net/http"
	"runtime/debug"
)

type versionInfo struct {
	Service   string `json:"service"`
	SHA       string `json:"sha"`
	Version   string `json:"version"`
	GoVersion string `json:"go_version"`
	BuiltAt   string `json:"built_at"`
}

// handleVersion returns a pre-computed JSON response built at startup from
// runtime/debug VCS metadata (injected by go build via vcs.revision / vcs.time).
// Falls back to "dev" when metadata is absent (local builds without git tag).
func handleVersion(service string) http.HandlerFunc {
	v := versionInfo{
		Service: service,
		SHA:     "dev",
		Version: "dev",
	}

	if bi, ok := debug.ReadBuildInfo(); ok {
		v.GoVersion = bi.GoVersion
		for _, s := range bi.Settings {
			switch s.Key {
			case "vcs.revision":
				if len(s.Value) >= 12 {
					v.SHA = s.Value[:12]
				} else if s.Value != "" {
					v.SHA = s.Value
				}
				v.Version = v.SHA
			case "vcs.time":
				v.BuiltAt = s.Value
			}
		}
	}

	payload, _ := json.Marshal(v)

	return func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write(payload)
	}
}
