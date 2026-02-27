package ws

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"sync"
	"time"

	"github.com/gorilla/websocket"

	natsclient "github.com/hasbegun/eyed/gateway/internal/nats"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true // Allow all origins for dev; tighten for production
	},
}

// Hub manages WebSocket clients and broadcasts NATS results to them.
type Hub struct {
	mu      sync.RWMutex
	clients map[*websocket.Conn]struct{}
	logger  *slog.Logger
}

// NewHub creates a WebSocket hub.
func NewHub(logger *slog.Logger) *Hub {
	return &Hub{
		clients: make(map[*websocket.Conn]struct{}),
		logger:  logger,
	}
}

// HandleWS upgrades the HTTP connection to a WebSocket and registers the client.
func (h *Hub) HandleWS(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		h.logger.Error("WebSocket upgrade failed", "error", err)
		return
	}

	h.mu.Lock()
	h.clients[conn] = struct{}{}
	count := len(h.clients)
	h.mu.Unlock()

	h.logger.Info("WebSocket client connected", "clients", count)

	// Read loop: discard incoming messages, detect disconnect
	go func() {
		defer func() {
			h.mu.Lock()
			delete(h.clients, conn)
			remaining := len(h.clients)
			h.mu.Unlock()
			conn.Close()
			h.logger.Info("WebSocket client disconnected", "clients", remaining)
		}()
		conn.SetReadDeadline(time.Now().Add(60 * time.Second))
		conn.SetPongHandler(func(string) error {
			conn.SetReadDeadline(time.Now().Add(60 * time.Second))
			return nil
		})
		for {
			if _, _, err := conn.ReadMessage(); err != nil {
				break
			}
		}
	}()

	// Ping loop to keep the connection alive
	go func() {
		ticker := time.NewTicker(30 * time.Second)
		defer ticker.Stop()
		for range ticker.C {
			h.mu.RLock()
			_, exists := h.clients[conn]
			h.mu.RUnlock()
			if !exists {
				return
			}
			if err := conn.WriteControl(websocket.PingMessage, nil, time.Now().Add(5*time.Second)); err != nil {
				return
			}
		}
	}()
}

// Broadcast sends a NATS AnalyzeResponse to all connected WebSocket clients.
func (h *Hub) Broadcast(resp *natsclient.AnalyzeResponse) {
	data, err := json.Marshal(resp)
	if err != nil {
		h.logger.Error("Failed to marshal result for WebSocket", "error", err)
		return
	}

	h.mu.RLock()
	clients := make([]*websocket.Conn, 0, len(h.clients))
	for c := range h.clients {
		clients = append(clients, c)
	}
	h.mu.RUnlock()

	for _, c := range clients {
		if err := c.WriteMessage(websocket.TextMessage, data); err != nil {
			h.logger.Debug("WebSocket write failed, removing client", "error", err)
			h.mu.Lock()
			delete(h.clients, c)
			h.mu.Unlock()
			c.Close()
		}
	}
}

// ClientCount returns the number of connected WebSocket clients.
func (h *Hub) ClientCount() int {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return len(h.clients)
}

// Register adds the WebSocket route to the given mux.
func (h *Hub) Register(mux *http.ServeMux) {
	mux.HandleFunc("/ws/results", h.HandleWS)
}
