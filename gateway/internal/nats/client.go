package nats

import (
	"encoding/json"
	"fmt"
	"log/slog"
	"sync/atomic"
	"time"

	"github.com/nats-io/nats.go"
)

// AnalyzeRequest matches the iris-engine's expected JSON schema on eyed.analyze.
type AnalyzeRequest struct {
	FrameID      string  `json:"frame_id"`
	DeviceID     string  `json:"device_id"`
	JPEGB64      string  `json:"jpeg_b64"`
	QualityScore float32 `json:"quality_score"`
	EyeSide      string  `json:"eye_side"`
	Timestamp    string  `json:"timestamp"`
}

// AnalyzeResponse matches the iris-engine's JSON schema on eyed.result.
type AnalyzeResponse struct {
	FrameID        string      `json:"frame_id"`
	DeviceID       string      `json:"device_id"`
	Match          *MatchInfo  `json:"match,omitempty"`
	IrisTemplateB64 string     `json:"iris_template_b64,omitempty"`
	LatencyMS      float64     `json:"latency_ms"`
	Error          string      `json:"error,omitempty"`
}

// MatchInfo represents a gallery match result.
type MatchInfo struct {
	HammingDistance   float64 `json:"hamming_distance"`
	IsMatch          bool    `json:"is_match"`
	MatchedIdentityID string  `json:"matched_identity_id,omitempty"`
	BestRotation     int     `json:"best_rotation"`
}

// ResultHandler is called when an analysis result arrives from iris-engine.
type ResultHandler func(resp *AnalyzeResponse)

// Client wraps a NATS connection for the gateway's pub/sub needs.
type Client struct {
	conn       *nats.Conn
	sub        *nats.Subscription
	published  atomic.Uint64
	logger     *slog.Logger
}

// Connect establishes a NATS connection with automatic reconnection.
func Connect(url string, logger *slog.Logger) (*Client, error) {
	opts := []nats.Option{
		nats.Name("eyed-gateway"),
		nats.MaxReconnects(-1),
		nats.ReconnectWait(2 * time.Second),
		nats.DisconnectErrHandler(func(_ *nats.Conn, err error) {
			logger.Warn("NATS disconnected", "error", err)
		}),
		nats.ReconnectHandler(func(_ *nats.Conn) {
			logger.Info("NATS reconnected")
		}),
	}

	conn, err := nats.Connect(url, opts...)
	if err != nil {
		return nil, fmt.Errorf("nats connect: %w", err)
	}

	logger.Info("Connected to NATS", "url", url)
	return &Client{conn: conn, logger: logger}, nil
}

// PublishAnalyze sends an AnalyzeRequest to eyed.analyze.
func (c *Client) PublishAnalyze(req *AnalyzeRequest) error {
	data, err := json.Marshal(req)
	if err != nil {
		return fmt.Errorf("marshal analyze request: %w", err)
	}
	if err := c.conn.Publish("eyed.analyze", data); err != nil {
		return fmt.Errorf("nats publish: %w", err)
	}
	c.published.Add(1)
	return nil
}

// SubscribeResults subscribes to eyed.result and calls handler for each message.
func (c *Client) SubscribeResults(handler ResultHandler) error {
	sub, err := c.conn.Subscribe("eyed.result", func(msg *nats.Msg) {
		var resp AnalyzeResponse
		if err := json.Unmarshal(msg.Data, &resp); err != nil {
			c.logger.Error("Failed to unmarshal result", "error", err)
			return
		}
		handler(&resp)
	})
	if err != nil {
		return fmt.Errorf("nats subscribe: %w", err)
	}
	c.sub = sub
	c.logger.Info("Subscribed to eyed.result")
	return nil
}

// IsConnected returns true if the NATS connection is active.
func (c *Client) IsConnected() bool {
	return c.conn != nil && c.conn.IsConnected()
}

// Published returns the total number of messages published.
func (c *Client) Published() uint64 {
	return c.published.Load()
}

// Close drains the connection and disconnects.
func (c *Client) Close() {
	if c.conn != nil {
		c.conn.Drain()
		c.logger.Info("NATS connection drained")
	}
}
