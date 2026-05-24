package yurtici

import (
	"bytes"
	"context"
	"encoding/xml"
	"fmt"
	"io"
	"net/http"
	"time"
)

// soapEnvelope wraps a generic body element for SOAP 1.1.
type soapEnvelope struct {
	XMLName xml.Name    `xml:"Envelope"`
	NS      string      `xml:"xmlns,attr"`
	Header  soapHeader  `xml:"Header"`
	Body    soapBodyRaw `xml:"Body"`
}

type soapHeader struct {
	Security wsseSecurity `xml:"Security"`
}

type wsseSecurity struct {
	NS            string        `xml:"xmlns:wsse,attr"`
	UsernameToken usernameToken `xml:"UsernameToken"`
}

type usernameToken struct {
	Username string `xml:"Username"`
	Password string `xml:"Password"`
}

type soapBodyRaw struct {
	InnerXML []byte `xml:",innerxml"`
}

// doSOAP sends a SOAP 1.1 request with WS-Security UsernameToken and decodes the body into out.
func doSOAP(ctx context.Context, httpClient *http.Client, endpoint, username, password, soapAction string, bodyXML []byte, out any) error {
	env := soapEnvelope{
		NS: "http://schemas.xmlsoap.org/soap/envelope/",
		Header: soapHeader{
			Security: wsseSecurity{
				NS: "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd",
				UsernameToken: usernameToken{
					Username: username,
					Password: password,
				},
			},
		},
		Body: soapBodyRaw{InnerXML: bodyXML},
	}
	payload, err := xml.MarshalIndent(env, "", "  ")
	if err != nil {
		return fmt.Errorf("yurtici: soap marshal: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "text/xml; charset=utf-8")
	req.Header.Set("SOAPAction", soapAction)

	resp, err := httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("yurtici: soap request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		return fmt.Errorf("yurtici: soap status %d", resp.StatusCode)
	}

	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("yurtici: soap read: %w", err)
	}

	// Unwrap outer SOAP envelope then decode inner result.
	type responseEnvelope struct {
		Body struct {
			InnerXML []byte `xml:",innerxml"`
		} `xml:"Body"`
	}
	var re responseEnvelope
	if err := xml.Unmarshal(raw, &re); err != nil {
		return fmt.Errorf("yurtici: soap unmarshal envelope: %w", err)
	}
	if out != nil {
		return xml.Unmarshal(re.Body.InnerXML, out)
	}
	return nil
}

// ── Track request / response DTOs ────────────────────────────────────────────

type trackRequest struct {
	XMLName      xml.Name `xml:"TrackShipment"`
	QueryNumber  string   `xml:"QueryNumber"`
	CustomerCode string   `xml:"CustomerCode"`
}

type trackResponse struct {
	XMLName     xml.Name `xml:"TrackShipmentResponse"`
	StatusCode  string   `xml:"StatusCode"`
	Description string   `xml:"Description"`
	EventDate   string   `xml:"EventDate"` // "2006-01-02T15:04:05"
}

// ── CreateLabel request / response DTOs ──────────────────────────────────────

type createLabelRequest struct {
	XMLName        xml.Name `xml:"CreateShipment"`
	CustomerCode   string   `xml:"CustomerCode"`
	OrderID        int64    `xml:"OrderID"`
	IdempotencyKey string   `xml:"IdempotencyKey"`
	WeightGrams    int      `xml:"WeightGrams"`
}

type createLabelResponse struct {
	XMLName           xml.Name `xml:"CreateShipmentResponse"`
	TrackingNumber    string   `xml:"TrackingNumber"`
	CarrierShipmentID string   `xml:"ShipmentID"`
	LabelPDF          string   `xml:"LabelPDFBase64"`
	CostMinor         int64    `xml:"CostMinor"`
	Currency          string   `xml:"Currency"`
}

const yurticiDateLayout = "2006-01-02T15:04:05"

var yurticiStateMap = map[string]string{
	"10": "picked_up",
	"20": "in_transit",
	"30": "out_for_delivery",
	"40": "delivered",
	"50": "returned",
	"60": "cancelled",
}

func mapYurticiState(code string) string {
	if s, ok := yurticiStateMap[code]; ok {
		return s
	}
	return "in_transit"
}

func parseYurticiDate(s string) time.Time {
	t, _ := time.ParseInLocation(yurticiDateLayout, s, time.UTC)
	return t
}
