// Package netgsm implements the SMS Provider interface for Netgsm (TR SMS gateway).
// Active when SMS_PROVIDER=netgsm.
package netgsm

import (
	"context"
	"encoding/xml"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/mopro/platform/internal/identity"
	"github.com/mopro/platform/pkg/slack"
)

// Provider sends SMS via the Netgsm XML API.
type Provider struct {
	username   string
	password   string
	header     string // alphanumeric sender ID approved by Netgsm
	apiURL     string
	http       *http.Client
	slackAlert *slack.Client
}

// New returns a Netgsm SMS provider.
// slackAlert is used to post a Slack message when ErrSMSInsufficientBalance is returned;
// pass slack.NewNoop() to disable alerting.
func New(username, password, header, apiURL string, slackAlert *slack.Client) *Provider {
	if apiURL == "" {
		apiURL = "https://api.netgsm.com.tr/sms/send/get"
	}
	return &Provider{
		username:   username,
		password:   password,
		header:     header,
		apiURL:     apiURL,
		http:       &http.Client{Timeout: 10 * time.Second},
		slackAlert: slackAlert,
	}
}

// Send delivers an OTP SMS. Maps Netgsm error codes to typed sentinels.
func (p *Provider) Send(ctx context.Context, toE164 string, code string) error {
	// Strip leading + from E.164 for Netgsm (expects plain digits).
	phone := strings.TrimPrefix(toE164, "+")
	msg := fmt.Sprintf("Doğrulama kodunuz: %s", code)

	params := url.Values{
		"usercode": {p.username},
		"password": {p.password},
		"gsmno":    {phone},
		"message":  {msg},
		"msgheader": {p.header},
		"dil":       {"TR"},
	}
	reqURL := p.apiURL + "?" + params.Encode()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, reqURL, nil)
	if err != nil {
		return fmt.Errorf("netgsm: build request: %w", err)
	}
	resp, err := p.http.Do(req)
	if err != nil {
		return fmt.Errorf("%w: %v", identity.ErrSMSSendFailed, err)
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
	return p.parseResponse(ctx, strings.TrimSpace(string(body)))
}

type netgsmResponse struct {
	Code string `xml:",chardata"`
}

func (p *Provider) parseResponse(ctx context.Context, body string) error {
	// Netgsm returns a code: "00" or "01" = success; others = error.
	var r netgsmResponse
	if err := xml.Unmarshal([]byte("<r>"+body+"</r>"), &r); err != nil {
		// Plain text response (non-XML mode also used by some endpoints)
		r.Code = body
	}
	code := strings.TrimSpace(r.Code)
	switch code {
	case "00", "01":
		return nil
	case "40": // insufficient credit
		_ = p.slackAlert.Post(ctx, slack.Message{
			Text: ":rotating_light: *Netgsm SMS* — insufficient balance. Top up immediately to restore OTP delivery.",
		})
		return identity.ErrSMSInsufficientBalance
	case "20":
		return fmt.Errorf("%w: netgsm auth failed (code 20)", identity.ErrSMSSendFailed)
	case "70":
		return fmt.Errorf("%w: netgsm invalid parameters (code 70)", identity.ErrSMSSendFailed)
	default:
		return fmt.Errorf("%w: netgsm error code %q", identity.ErrSMSSendFailed, code)
	}
}
