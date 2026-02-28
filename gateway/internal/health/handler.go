package health

import (
	"encoding/json"
	"net/http"

	"github.com/hasbegun/eyed/gateway/internal/breaker"
	natsclient "github.com/hasbegun/eyed/gateway/internal/nats"
)

type aliveResponse struct {
	Alive bool `json:"alive"`
}

type readyResponse struct {
	Alive          bool   `json:"alive"`
	Ready          bool   `json:"ready"`
	NatsConnected  bool   `json:"nats_connected"`
	CircuitBreaker string `json:"circuit_breaker"`
	Version        string `json:"version"`
}

// Handler serves HTTP health check endpoints.
type Handler struct {
	nats    *natsclient.Client
	breaker *breaker.Breaker
}

// NewHandler creates health check HTTP handlers.
func NewHandler(nc *natsclient.Client, cb *breaker.Breaker) *Handler {
	return &Handler{nats: nc, breaker: cb}
}

// Register adds health routes to the given mux.
func (h *Handler) Register(mux *http.ServeMux) {
	mux.HandleFunc("/health/alive", h.alive)
	mux.HandleFunc("/health/ready", h.ready)
}

func (h *Handler) alive(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, aliveResponse{Alive: true})
}

func (h *Handler) ready(w http.ResponseWriter, _ *http.Request) {
	connected := h.nats.IsConnected()
	cbState := h.breaker.State()
	writeJSON(w, readyResponse{
		Alive:          true,
		Ready:          connected && cbState == breaker.Closed,
		NatsConnected:  connected,
		CircuitBreaker: cbState.String(),
		Version:        "0.1.0",
	})
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(v)
}
