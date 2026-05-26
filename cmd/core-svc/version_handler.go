package main

import (
	"encoding/json"
	"net/http"
	"runtime/debug"

	"github.com/mopro/platform/internal/buildinfo"
)

type versionInfo struct {
	Service   string `json:"service"`
	SHA       string `json:"sha"`
	Version   string `json:"version"`
	GoVersion string `json:"go_version"`
	BuiltAt   string `json:"built_at"`
}

// handleVersion returns a pre-computed JSON response built at startup.
// Priority: ldflags-injected buildinfo (CI/tarball builds) > vcs.revision from
// debug.ReadBuildInfo() (local git builds) > "dev" fallback.
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

	// ldflags take precedence over VCS metadata — covers CI and tarball builds
	// where .git is absent. buildinfo.SHA is the full 40-char commit hash.
	if buildinfo.SHA != "" {
		sha := buildinfo.SHA
		if len(sha) > 12 {
			sha = sha[:12]
		}
		v.SHA = sha
		v.Version = sha
	}
	if buildinfo.BuiltAt != "" {
		v.BuiltAt = buildinfo.BuiltAt
	}

	payload, _ := json.Marshal(v)

	return func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write(payload)
	}
}
