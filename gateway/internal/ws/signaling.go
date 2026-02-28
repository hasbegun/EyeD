package ws

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

// SignalMessage is the JSON envelope for WebRTC signaling messages.
type SignalMessage struct {
	Type     string          `json:"type"`      // "offer", "answer", "ice-candidate", "join", "leave"
	DeviceID string          `json:"device_id"` // Which capture device this relates to
	From     string          `json:"from"`      // Sender role: "device" or "viewer"
	Payload  json.RawMessage `json:"payload"`   // SDP or ICE candidate data
}

type sigClient struct {
	conn     *websocket.Conn
	deviceID string
	role     string // "device" or "viewer"
}

// SignalingHub relays WebRTC signaling messages between capture devices and browser viewers.
//
// Protocol:
//   - Capture device connects to /ws/signaling?device_id=X&role=device
//   - Browser connects to /ws/signaling?device_id=X&role=viewer
//   - Messages from device are forwarded to all viewers of that device
//   - Messages from viewer are forwarded to the device
type SignalingHub struct {
	mu      sync.RWMutex
	devices map[string]*sigClient            // device_id → device connection
	viewers map[string]map[*sigClient]struct{} // device_id → set of viewers
	logger  *slog.Logger
}

// NewSignalingHub creates a WebRTC signaling relay.
func NewSignalingHub(logger *slog.Logger) *SignalingHub {
	return &SignalingHub{
		devices: make(map[string]*sigClient),
		viewers: make(map[string]map[*sigClient]struct{}),
		logger:  logger,
	}
}

// HandleSignaling upgrades the HTTP connection and routes signaling messages.
func (h *SignalingHub) HandleSignaling(w http.ResponseWriter, r *http.Request) {
	deviceID := r.URL.Query().Get("device_id")
	role := r.URL.Query().Get("role")

	if deviceID == "" || (role != "device" && role != "viewer") {
		http.Error(w, `{"error":"device_id and role (device|viewer) required"}`, http.StatusBadRequest)
		return
	}

	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		h.logger.Error("Signaling WebSocket upgrade failed", "error", err)
		return
	}

	client := &sigClient{conn: conn, deviceID: deviceID, role: role}

	h.register(client)
	defer h.unregister(client)

	h.logger.Info("Signaling client connected", "device_id", deviceID, "role", role)

	// Notify peers about the new connection
	h.broadcastPresence(client, "join")

	conn.SetReadDeadline(time.Now().Add(60 * time.Second))
	conn.SetPongHandler(func(string) error {
		conn.SetReadDeadline(time.Now().Add(60 * time.Second))
		return nil
	})

	// Ping loop
	go func() {
		ticker := time.NewTicker(30 * time.Second)
		defer ticker.Stop()
		for range ticker.C {
			if err := conn.WriteControl(websocket.PingMessage, nil, time.Now().Add(5*time.Second)); err != nil {
				return
			}
		}
	}()

	// Read loop: relay messages to peers
	for {
		_, raw, err := conn.ReadMessage()
		if err != nil {
			break
		}

		var msg SignalMessage
		if err := json.Unmarshal(raw, &msg); err != nil {
			h.logger.Debug("Invalid signaling message", "error", err)
			continue
		}

		msg.DeviceID = deviceID // Enforce device_id from URL
		msg.From = role

		h.relay(client, &msg)
	}

	h.broadcastPresence(client, "leave")
	h.logger.Info("Signaling client disconnected", "device_id", deviceID, "role", role)
}

func (h *SignalingHub) register(c *sigClient) {
	h.mu.Lock()
	defer h.mu.Unlock()

	if c.role == "device" {
		h.devices[c.deviceID] = c
	} else {
		if h.viewers[c.deviceID] == nil {
			h.viewers[c.deviceID] = make(map[*sigClient]struct{})
		}
		h.viewers[c.deviceID][c] = struct{}{}
	}
}

func (h *SignalingHub) unregister(c *sigClient) {
	h.mu.Lock()
	defer h.mu.Unlock()

	if c.role == "device" {
		if h.devices[c.deviceID] == c {
			delete(h.devices, c.deviceID)
		}
	} else {
		if viewers, ok := h.viewers[c.deviceID]; ok {
			delete(viewers, c)
			if len(viewers) == 0 {
				delete(h.viewers, c.deviceID)
			}
		}
	}
	c.conn.Close()
}

// relay forwards a signaling message to the appropriate peer(s).
func (h *SignalingHub) relay(sender *sigClient, msg *SignalMessage) {
	data, err := json.Marshal(msg)
	if err != nil {
		return
	}

	h.mu.RLock()
	defer h.mu.RUnlock()

	if sender.role == "device" {
		// Device → all viewers
		for viewer := range h.viewers[sender.deviceID] {
			viewer.conn.WriteMessage(websocket.TextMessage, data)
		}
	} else {
		// Viewer → device
		if dev, ok := h.devices[sender.deviceID]; ok {
			dev.conn.WriteMessage(websocket.TextMessage, data)
		}
	}
}

// broadcastPresence notifies peers about a client joining or leaving.
func (h *SignalingHub) broadcastPresence(c *sigClient, eventType string) {
	msg := SignalMessage{
		Type:     eventType,
		DeviceID: c.deviceID,
		From:     c.role,
	}
	data, _ := json.Marshal(msg)

	h.mu.RLock()
	defer h.mu.RUnlock()

	if c.role == "device" {
		for viewer := range h.viewers[c.deviceID] {
			viewer.conn.WriteMessage(websocket.TextMessage, data)
		}
	} else {
		if dev, ok := h.devices[c.deviceID]; ok {
			dev.conn.WriteMessage(websocket.TextMessage, data)
		}
	}
}

// Register adds the signaling route to the given mux.
func (h *SignalingHub) Register(mux *http.ServeMux) {
	mux.HandleFunc("/ws/signaling", h.HandleSignaling)
}

// DeviceCount returns the number of connected capture devices.
func (h *SignalingHub) DeviceCount() int {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return len(h.devices)
}

// ViewerCount returns the total number of connected viewers.
func (h *SignalingHub) ViewerCount() int {
	h.mu.RLock()
	defer h.mu.RUnlock()
	total := 0
	for _, viewers := range h.viewers {
		total += len(viewers)
	}
	return total
}
