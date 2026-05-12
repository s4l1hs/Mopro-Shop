package ptt

import (
	"bytes"
	"context"
	"encoding/xml"
	"fmt"
	"io"
	"net/http"
	"time"
)

// doSOAP sends a SOAP 1.1 request (no WS-Security header — PTT uses credential elements in body).
func doSOAP(ctx context.Context, httpClient *http.Client, endpoint, soapAction string, bodyXML []byte, out any) error {
	type soapBodyRaw struct {
		InnerXML []byte `xml:",innerxml"`
	}
	type envelope struct {
		XMLName xml.Name    `xml:"Envelope"`
		NS      string      `xml:"xmlns,attr"`
		Body    soapBodyRaw `xml:"Body"`
	}

	env := envelope{
		NS:   "http://schemas.xmlsoap.org/soap/envelope/",
		Body: soapBodyRaw{InnerXML: bodyXML},
	}
	payload, err := xml.MarshalIndent(env, "", "  ")
	if err != nil {
		return fmt.Errorf("ptt: soap marshal: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "text/xml; charset=utf-8")
	req.Header.Set("SOAPAction", soapAction)

	resp, err := httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("ptt: soap request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		return fmt.Errorf("ptt: soap status %d", resp.StatusCode)
	}

	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("ptt: soap read: %w", err)
	}

	type responseEnvelope struct {
		Body struct {
			InnerXML []byte `xml:",innerxml"`
		} `xml:"Body"`
	}
	var re responseEnvelope
	if err := xml.Unmarshal(raw, &re); err != nil {
		return fmt.Errorf("ptt: soap unmarshal: %w", err)
	}
	if out != nil {
		return xml.Unmarshal(re.Body.InnerXML, out)
	}
	return nil
}

// ── DTOs ──────────────────────────────────────────────────────────────────────

type trackRequest struct {
	XMLName      xml.Name `xml:"TrackShipment"`
	Username     string   `xml:"Username"`
	Password     string   `xml:"Password"`
	CustomerCode string   `xml:"CustomerCode"`
	Barcode      string   `xml:"Barcode"`
}

type trackResponse struct {
	XMLName     xml.Name `xml:"TrackShipmentResponse"`
	StatusCode  string   `xml:"StatusCode"`
	Description string   `xml:"Description"`
	EventDate   string   `xml:"EventDate"`
}

type createLabelRequest struct {
	XMLName        xml.Name `xml:"CreateShipment"`
	Username       string   `xml:"Username"`
	Password       string   `xml:"Password"`
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

var pttStateMap = map[string]string{
	"10": "picked_up",
	"20": "in_transit",
	"30": "out_for_delivery",
	"40": "delivered",
	"50": "returned",
	"60": "cancelled",
}

func mapPTTState(code string) string {
	if s, ok := pttStateMap[code]; ok {
		return s
	}
	return "in_transit"
}

func parsePTTDate(s string) time.Time {
	t, _ := time.ParseInLocation("2006-01-02T15:04:05", s, time.UTC)
	return t
}
