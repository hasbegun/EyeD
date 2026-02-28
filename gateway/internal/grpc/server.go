package grpc

import (
	"context"
	"encoding/base64"
	"fmt"
	"io"
	"log/slog"
	"sync/atomic"
	"time"

	"github.com/hasbegun/eyed/gateway/internal/breaker"
	natsclient "github.com/hasbegun/eyed/gateway/internal/nats"
	pb "github.com/hasbegun/eyed/gateway/proto/eyed"
)

// Server implements the CaptureService gRPC interface.
type Server struct {
	pb.UnimplementedCaptureServiceServer
	nats    *natsclient.Client
	breaker *breaker.Breaker
	logger  *slog.Logger

	framesProcessed  atomic.Uint64
	framesRejected   atomic.Uint64
	connectedDevices atomic.Int32
	totalLatencyUS   atomic.Int64
}

// NewServer creates a gRPC CaptureService backed by the given NATS client.
func NewServer(nc *natsclient.Client, cb *breaker.Breaker, logger *slog.Logger) *Server {
	return &Server{nats: nc, breaker: cb, logger: logger}
}

// SubmitFrame handles a single frame submission from a capture device.
func (s *Server) SubmitFrame(_ context.Context, frame *pb.CaptureFrame) (*pb.FrameAck, error) {
	if !s.breaker.Allow() {
		s.framesRejected.Add(1)
		s.logger.Warn("Circuit breaker open, rejecting frame",
			"frame_id", frame.FrameId,
			"device_id", frame.DeviceId,
			"state", s.breaker.State().String(),
		)
		return &pb.FrameAck{
			FrameId:  frame.FrameId,
			Accepted: false,
		}, nil
	}

	start := time.Now()

	req := &natsclient.AnalyzeRequest{
		FrameID:      fmt.Sprintf("%d", frame.FrameId),
		DeviceID:     frame.DeviceId,
		JPEGB64:      base64.StdEncoding.EncodeToString(frame.JpegData),
		QualityScore: frame.QualityScore,
		EyeSide:      frame.EyeSide,
		Timestamp:    time.UnixMicro(int64(frame.TimestampUs)).UTC().Format(time.RFC3339Nano),
	}

	if err := s.nats.PublishAnalyze(req); err != nil {
		s.logger.Error("Failed to publish frame", "frame_id", frame.FrameId, "error", err)
		return &pb.FrameAck{
			FrameId:  frame.FrameId,
			Accepted: false,
		}, nil
	}

	s.framesProcessed.Add(1)
	elapsed := time.Since(start).Microseconds()
	s.totalLatencyUS.Add(elapsed)

	s.logger.Debug("Frame submitted",
		"frame_id", frame.FrameId,
		"device_id", frame.DeviceId,
		"latency_us", elapsed,
	)

	return &pb.FrameAck{
		FrameId:    frame.FrameId,
		Accepted:   true,
		QueueDepth: 0,
	}, nil
}

// StreamFrames handles bidirectional streaming of frames.
func (s *Server) StreamFrames(stream pb.CaptureService_StreamFramesServer) error {
	s.connectedDevices.Add(1)
	defer s.connectedDevices.Add(-1)

	s.logger.Info("Streaming client connected")

	for {
		frame, err := stream.Recv()
		if err == io.EOF {
			s.logger.Info("Streaming client disconnected (EOF)")
			return nil
		}
		if err != nil {
			s.logger.Error("Stream receive error", "error", err)
			return err
		}

		ack, _ := s.SubmitFrame(nil, frame)
		if err := stream.Send(ack); err != nil {
			s.logger.Error("Stream send error", "error", err)
			return err
		}
	}
}

// GetStatus returns server metrics.
func (s *Server) GetStatus(_ context.Context, _ *pb.Empty) (*pb.ServerStatus, error) {
	processed := s.framesProcessed.Load()
	var avgLatency float32
	if processed > 0 {
		avgLatency = float32(s.totalLatencyUS.Load()) / float32(processed) / 1000.0
	}

	return &pb.ServerStatus{
		Alive:            true,
		Ready:            s.nats.IsConnected(),
		ConnectedDevices: uint32(s.connectedDevices.Load()),
		AvgLatencyMs:     avgLatency,
		FramesProcessed:  processed,
	}, nil
}
