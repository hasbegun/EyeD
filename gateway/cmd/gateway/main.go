package main

import (
	"context"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"google.golang.org/grpc"

	"github.com/hasbegun/eyed/gateway/internal/breaker"
	"github.com/hasbegun/eyed/gateway/internal/config"
	grpcserver "github.com/hasbegun/eyed/gateway/internal/grpc"
	"github.com/hasbegun/eyed/gateway/internal/health"
	natsclient "github.com/hasbegun/eyed/gateway/internal/nats"
	"github.com/hasbegun/eyed/gateway/internal/ws"
	pb "github.com/hasbegun/eyed/gateway/proto/eyed"
)

// corsMiddleware allows cross-origin requests from the Flutter web client.
func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func main() {
	cfg := config.Load()

	var level slog.Level
	switch cfg.LogLevel {
	case "debug":
		level = slog.LevelDebug
	case "warn":
		level = slog.LevelWarn
	case "error":
		level = slog.LevelError
	default:
		level = slog.LevelInfo
	}
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: level}))
	slog.SetDefault(logger)

	// Connect to NATS
	nc, err := natsclient.Connect(cfg.NatsURL, logger)
	if err != nil {
		logger.Error("Failed to connect to NATS", "error", err)
		os.Exit(1)
	}
	defer nc.Close()

	// Circuit breaker: trips after 30s of no results, probes every 10s
	cb := breaker.New(30*time.Second, 10*time.Second)
	logger.Info("Circuit breaker initialized", "timeout", "30s", "probe_interval", "10s")

	// WebSocket hub for broadcasting results to browser clients
	wsHub := ws.NewHub(logger)

	// Subscribe to NATS results — log + broadcast + reset circuit breaker
	if err := nc.SubscribeResults(func(resp *natsclient.AnalyzeResponse) {
		cb.RecordResult()
		if resp.Error != "" {
			logger.Warn("Analysis error",
				"frame_id", resp.FrameID,
				"error", resp.Error,
			)
		} else if resp.Match != nil && resp.Match.IsMatch {
			logger.Info("Analysis match",
				"frame_id", resp.FrameID,
				"device_id", resp.DeviceID,
				"latency_ms", resp.LatencyMS,
				"identity", resp.Match.MatchedIdentityID,
				"hamming", resp.Match.HammingDistance,
			)
		} else {
			logger.Debug("Analysis result",
				"frame_id", resp.FrameID,
				"device_id", resp.DeviceID,
				"latency_ms", resp.LatencyMS,
			)
		}
		wsHub.Broadcast(resp)
	}); err != nil {
		logger.Error("Failed to subscribe to results", "error", err)
		os.Exit(1)
	}

	// Start gRPC server
	grpcLis, err := net.Listen("tcp", ":"+cfg.GRPCPort)
	if err != nil {
		logger.Error("Failed to listen on gRPC port", "port", cfg.GRPCPort, "error", err)
		os.Exit(1)
	}
	grpcSrv := grpc.NewServer()
	captureSrv := grpcserver.NewServer(nc, cb, logger)
	pb.RegisterCaptureServiceServer(grpcSrv, captureSrv)

	go func() {
		logger.Info("gRPC server listening", "port", cfg.GRPCPort)
		if err := grpcSrv.Serve(grpcLis); err != nil {
			logger.Error("gRPC server error", "error", err)
		}
	}()

	// WebRTC signaling relay (capture device ↔ browser)
	sigHub := ws.NewSignalingHub(logger)

	// Start HTTP server (health + WebSocket + signaling)
	mux := http.NewServeMux()
	health.NewHandler(nc, cb).Register(mux)
	wsHub.Register(mux)
	sigHub.Register(mux)
	httpSrv := &http.Server{Addr: ":" + cfg.HTTPPort, Handler: corsMiddleware(mux)}

	go func() {
		logger.Info("HTTP health server listening", "port", cfg.HTTPPort)
		if err := httpSrv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Error("HTTP server error", "error", err)
		}
	}()

	// Wait for shutdown signal
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	sig := <-sigCh
	logger.Info("Shutting down", "signal", sig)

	grpcSrv.GracefulStop()
	httpSrv.Shutdown(context.Background())
	logger.Info("Shutdown complete")
}
