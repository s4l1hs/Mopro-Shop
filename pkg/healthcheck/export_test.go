package healthcheck

// GetPingerBaseURL extracts the base URL from an httpPinger for white-box testing.
// Returns empty string if p is not an *httpPinger.
func GetPingerBaseURL(p Pinger) string {
	h, ok := p.(*httpPinger)
	if !ok {
		return ""
	}
	return h.baseURL
}
