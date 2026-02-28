package archive

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log/slog"
	"strings"
	"sync/atomic"
	"time"

	"github.com/hasbegun/eyed/storage/internal/store"
	"github.com/nats-io/nats.go"
)

// ArchiveMessage is the JSON structure published by iris-engine on eyed.archive.
type ArchiveMessage struct {
	FrameID         string          `json:"frame_id"`
	DeviceID        string          `json:"device_id"`
	Timestamp       string          `json:"timestamp"`
	EyeSide         string          `json:"eye_side"`
	RawJPEGB64      string          `json:"raw_jpeg_b64"`
	QualityScore    float64         `json:"quality_score"`
	IrisTemplateB64 *string         `json:"iris_template_b64,omitempty"`
	LatencyMS       float64         `json:"latency_ms"`
	Error           *string         `json:"error,omitempty"`
	Segmentation    json.RawMessage `json:"segmentation,omitempty"`
	Match           json.RawMessage `json:"match,omitempty"`
}

// Metadata is the JSON file written alongside each raw JPEG.
type Metadata struct {
	FrameID    string          `json:"frame_id"`
	DeviceID   string          `json:"device_id"`
	Timestamp  string          `json:"timestamp"`
	EyeSide    string          `json:"eye_side"`
	Quality    float64         `json:"quality_score"`
	Pipeline   PipelineResult  `json:"pipeline_result"`
}

// PipelineResult holds the analysis output for the metadata file.
type PipelineResult struct {
	Segmentation json.RawMessage `json:"segmentation,omitempty"`
	Match        json.RawMessage `json:"match,omitempty"`
	LatencyMS    float64         `json:"latency_ms"`
	Error        *string         `json:"error,omitempty"`
}

// Handler processes NATS archive messages and writes files to the object store.
type Handler struct {
	store  store.ObjectStore
	logger *slog.Logger
	archived atomic.Int64
	errors   atomic.Int64
}

// NewHandler creates an archive handler.
func NewHandler(s store.ObjectStore, logger *slog.Logger) *Handler {
	return &Handler{store: s, logger: logger}
}

// HandleMessage is the NATS subscription callback.
func (h *Handler) HandleMessage(msg *nats.Msg) {
	var m ArchiveMessage
	if err := json.Unmarshal(msg.Data, &m); err != nil {
		h.errors.Add(1)
		h.logger.Error("Failed to unmarshal archive message", "error", err)
		return
	}

	if err := h.archive(&m); err != nil {
		h.errors.Add(1)
		h.logger.Error("Failed to archive frame",
			"frame_id", m.FrameID, "device_id", m.DeviceID, "error", err)
		return
	}

	h.archived.Add(1)
	h.logger.Debug("Archived frame",
		"frame_id", m.FrameID, "device_id", m.DeviceID)
}

func (h *Handler) archive(m *ArchiveMessage) error {
	// Derive date directory from timestamp
	date := extractDate(m.Timestamp)

	// Sanitize device_id and frame_id for safe filesystem paths
	deviceID := sanitizePath(m.DeviceID)
	frameID := sanitizePath(m.FrameID)

	// Write raw JPEG
	if m.RawJPEGB64 != "" {
		jpegData, err := base64.StdEncoding.DecodeString(m.RawJPEGB64)
		if err != nil {
			return fmt.Errorf("decode jpeg base64: %w", err)
		}
		jpegPath := fmt.Sprintf("raw/%s/%s/%s.jpg", date, deviceID, frameID)
		if err := h.store.Put(jpegPath, jpegData); err != nil {
			return fmt.Errorf("write jpeg: %w", err)
		}
	}

	// Write metadata JSON (everything except raw JPEG)
	meta := Metadata{
		FrameID:   m.FrameID,
		DeviceID:  m.DeviceID,
		Timestamp: m.Timestamp,
		EyeSide:   m.EyeSide,
		Quality:   m.QualityScore,
		Pipeline: PipelineResult{
			Segmentation: m.Segmentation,
			Match:        m.Match,
			LatencyMS:    m.LatencyMS,
			Error:        m.Error,
		},
	}

	metaJSON, err := json.MarshalIndent(meta, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal metadata: %w", err)
	}

	metaPath := fmt.Sprintf("raw/%s/%s/%s.meta.json", date, deviceID, frameID)
	if err := h.store.Put(metaPath, metaJSON); err != nil {
		return fmt.Errorf("write metadata: %w", err)
	}

	return nil
}

// Stats returns the number of archived frames and errors.
func (h *Handler) Stats() (archived, errors int64) {
	return h.archived.Load(), h.errors.Load()
}

// extractDate parses an ISO8601 timestamp and returns YYYY-MM-DD.
// Falls back to today's date if parsing fails.
func extractDate(ts string) string {
	t, err := time.Parse(time.RFC3339Nano, ts)
	if err != nil {
		t, err = time.Parse(time.RFC3339, ts)
	}
	if err != nil {
		t = time.Now().UTC()
	}
	return t.Format("2006-01-02")
}

// sanitizePath removes path separators and ".." from a string for safe file naming.
func sanitizePath(s string) string {
	s = strings.ReplaceAll(s, "/", "_")
	s = strings.ReplaceAll(s, "\\", "_")
	s = strings.ReplaceAll(s, "..", "_")
	if s == "" {
		s = "unknown"
	}
	return s
}
