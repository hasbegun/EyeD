package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/hasbegun/eyed/storage/internal/archive"
	"github.com/hasbegun/eyed/storage/internal/config"
	"github.com/hasbegun/eyed/storage/internal/retention"
	"github.com/hasbegun/eyed/storage/internal/store"
	"github.com/nats-io/nats.go"
)

func main() {
	cfg := config.Load()

	// Setup structured logging
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

	logger.Info("Starting EyeD storage service",
		"nats_url", cfg.NatsURL,
		"archive_root", cfg.ArchiveRoot,
		"retention_raw_days", cfg.RetentionRawDays,
	)

	// Initialize local filesystem store
	localStore, err := store.NewLocal(cfg.ArchiveRoot)
	if err != nil {
		logger.Error("Failed to initialize store", "error", err)
		os.Exit(1)
	}

	// Create archive handler
	handler := archive.NewHandler(localStore, logger)

	// Connect to NATS
	nc, err := nats.Connect(cfg.NatsURL,
		nats.MaxReconnects(-1),
		nats.ReconnectWait(2*time.Second),
		nats.DisconnectErrHandler(func(_ *nats.Conn, err error) {
			logger.Warn("NATS disconnected", "error", err)
		}),
		nats.ReconnectHandler(func(_ *nats.Conn) {
			logger.Info("NATS reconnected")
		}),
		nats.ClosedHandler(func(_ *nats.Conn) {
			logger.Info("NATS connection closed")
		}),
	)
	if err != nil {
		logger.Error("Failed to connect to NATS", "error", err)
		os.Exit(1)
	}
	defer nc.Drain()
	logger.Info("Connected to NATS", "url", cfg.NatsURL)

	// Subscribe to archive messages
	sub, err := nc.Subscribe("eyed.archive", handler.HandleMessage)
	if err != nil {
		logger.Error("Failed to subscribe to eyed.archive", "error", err)
		os.Exit(1)
	}
	_ = sub
	logger.Info("Subscribed to eyed.archive")

	// Start retention purger in background
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	purger := retention.NewPurger(localStore, cfg.RetentionRawDays, logger)
	go purger.Run(ctx)

	// HTTP health endpoint
	mux := http.NewServeMux()
	mux.HandleFunc("/health/alive", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{
			"alive": true,
		})
	})
	mux.HandleFunc("/health/ready", func(w http.ResponseWriter, r *http.Request) {
		archived, errors := handler.Stats()
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{
			"alive":          true,
			"ready":          nc.IsConnected(),
			"nats_connected": nc.IsConnected(),
			"archived":       archived,
			"errors":         errors,
			"version":        "0.1.0",
		})
	})

	httpSrv := &http.Server{Addr: ":" + cfg.HTTPPort, Handler: mux}
	go func() {
		logger.Info("HTTP health server listening", "port", cfg.HTTPPort)
		if err := httpSrv.ListenAndServe(); err != http.ErrServerClosed {
			logger.Error("HTTP server error", "error", err)
		}
	}()

	// Graceful shutdown
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	sig := <-sigCh
	logger.Info("Shutting down", "signal", sig.String())

	cancel() // stop purger

	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer shutdownCancel()
	httpSrv.Shutdown(shutdownCtx)

	archived, errors := handler.Stats()
	logger.Info("Storage service stopped",
		"total_archived", archived,
		"total_errors", errors,
	)
	fmt.Println("Shutdown complete")
}
