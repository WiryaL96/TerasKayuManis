package commerce

import (
	"encoding/base64"
	"encoding/json"
	"strings"
)

// Call only AFTER Supabase Auth has verified this exact bearer. This is an
// additional revocation/version check, never an alternative JWT authenticator.
func staffSessionVersion(bearer string) int {
	parts := strings.Split(strings.TrimPrefix(bearer, "Bearer "), ".")
	if len(parts) != 3 {
		return 0
	} // Auth-verified legacy sessions predate versioning.
	raw, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return -1
	}
	var claims struct {
		Meta struct {
			Version int `json:"staff_session_version"`
		} `json:"app_metadata"`
	}
	if json.Unmarshal(raw, &claims) != nil || claims.Meta.Version < 0 {
		return -1
	}
	return claims.Meta.Version
}
