package ptt_test

import (
	"context"
	"encoding/xml"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/mopro/platform/internal/shipping"
	"github.com/mopro/platform/internal/shipping/ptt"
)

func buildServer(t *testing.T) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		type trackResp struct {
			XMLName     xml.Name `xml:"TrackShipmentResponse"`
			StatusCode  string   `xml:"StatusCode"`
			Description string   `xml:"Description"`
			EventDate   string   `xml:"EventDate"`
		}
		inner, _ := xml.Marshal(trackResp{StatusCode: "40", Description: "Teslim edildi", EventDate: "2026-01-01T10:00:00"})

		type soapResp struct {
			XMLName xml.Name `xml:"Envelope"`
			NS      string   `xml:"xmlns,attr"`
			Body    struct {
				InnerXML []byte `xml:",innerxml"`
			} `xml:"Body"`
		}
		env := soapResp{NS: "http://schemas.xmlsoap.org/soap/envelope/"}
		env.Body.InnerXML = inner
		w.Header().Set("Content-Type", "text/xml")
		xml.NewEncoder(w).Encode(env)
	}))
}

func TestAdapter_TrackShipment_Delivered(t *testing.T) {
	srv := buildServer(t)
	defer srv.Close()

	a := ptt.New(shipping.PTTConfig{WSDLURL: srv.URL, Username: "u", Password: "p"})
	res, err := a.TrackShipment(context.Background(), "PTT-001")
	if err != nil {
		t.Fatalf("TrackShipment: %v", err)
	}
	if res.State != shipping.ShipmentStateDelivered {
		t.Errorf("state: want delivered, got %s", res.State)
	}
}

func TestAdapter_HandleWebhook_NotSupported(t *testing.T) {
	a := ptt.New(shipping.PTTConfig{})
	_, err := a.HandleWebhook(context.Background(), nil, nil)
	if err == nil {
		t.Error("expected error for unsupported webhook")
	}
}
