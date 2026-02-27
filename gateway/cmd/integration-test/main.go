// Integration test: sends a JPEG via gRPC to gateway, verifies iris-engine
// processes it and publishes the result on NATS eyed.result.
//
// Usage: /app/integration-test -gateway localhost:50051 -nats nats://nats:4222 -image /data/Iris/CASIA1/1/001_1_1.jpg
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/nats-io/nats.go"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"

	pb "github.com/hasbegun/eyed/gateway/proto/eyed"
)

type analyzeResponse struct {
	FrameID   string  `json:"frame_id"`
	DeviceID  string  `json:"device_id"`
	LatencyMS float64 `json:"latency_ms"`
	Error     string  `json:"error,omitempty"`
}

func main() {
	gatewayAddr := flag.String("gateway", "localhost:50051", "gateway gRPC address")
	natsURL := flag.String("nats", "nats://nats:4222", "NATS server URL")
	imagePath := flag.String("image", "/data/Iris/CASIA1/1/001_1_1.jpg", "JPEG image path")
	timeout := flag.Duration("timeout", 30*time.Second, "test timeout")
	flag.Parse()

	ctx, cancel := context.WithTimeout(context.Background(), *timeout)
	defer cancel()

	// 1. Connect to NATS and subscribe to eyed.result
	nc, err := nats.Connect(*natsURL)
	if err != nil {
		log.Fatalf("NATS connect: %v", err)
	}
	defer nc.Drain()

	resultCh := make(chan *analyzeResponse, 1)
	sub, err := nc.Subscribe("eyed.result", func(msg *nats.Msg) {
		var resp analyzeResponse
		if err := json.Unmarshal(msg.Data, &resp); err != nil {
			log.Printf("unmarshal result: %v", err)
			return
		}
		// Filter: only accept results from our test device
		if resp.DeviceID != "integration-test" {
			return
		}
		select {
		case resultCh <- &resp:
		default:
		}
	})
	if err != nil {
		log.Fatalf("NATS subscribe: %v", err)
	}
	defer sub.Unsubscribe()
	log.Println("Subscribed to eyed.result")

	// 2. Read JPEG image
	jpegData, err := os.ReadFile(*imagePath)
	if err != nil {
		log.Fatalf("read image %s: %v", *imagePath, err)
	}
	log.Printf("Read image: %s (%d bytes)", *imagePath, len(jpegData))

	// 3. Connect to gateway gRPC
	conn, err := grpc.NewClient(*gatewayAddr, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		log.Fatalf("gRPC connect: %v", err)
	}
	defer conn.Close()
	client := pb.NewCaptureServiceClient(conn)

	// 4. Wait for gateway to be ready (pipeline loaded + breaker closed)
	log.Println("Waiting for gateway to be ready...")
	for {
		st, err := client.GetStatus(ctx, &pb.Empty{})
		if err == nil && st.Ready {
			log.Println("Gateway ready")
			break
		}
		select {
		case <-ctx.Done():
			log.Fatal("FAIL: timeout waiting for gateway to become ready")
		case <-time.After(2 * time.Second):
		}
	}

	// 5. Send frame via gRPC (retry if breaker rejects)
	frame := &pb.CaptureFrame{
		JpegData:     jpegData,
		QualityScore: 0.5,
		TimestampUs:  uint64(time.Now().UnixMicro()),
		FrameId:      42,
		DeviceId:     "integration-test",
		EyeSide:      "left",
	}

	for {
		ack, err := client.SubmitFrame(ctx, frame)
		if err != nil {
			log.Fatalf("SubmitFrame: %v", err)
		}
		log.Printf("FrameAck: frame_id=%d accepted=%v", ack.FrameId, ack.Accepted)

		if ack.Accepted {
			break
		}
		// Breaker is open — wait for it to half-open and retry.
		log.Println("Breaker open, retrying in 5s...")
		select {
		case <-ctx.Done():
			log.Fatal("FAIL: timeout waiting for breaker to close")
		case <-time.After(5 * time.Second):
		}
	}

	// 6. Wait for result on NATS
	log.Println("Waiting for iris-engine result on eyed.result...")
	select {
	case resp := <-resultCh:
		log.Printf("Result: frame_id=%s device_id=%s latency_ms=%.1f error=%q",
			resp.FrameID, resp.DeviceID, resp.LatencyMS, resp.Error)

		if resp.Error != "" {
			// Segmentation failure on some images is acceptable
			log.Printf("WARN: pipeline error (may be expected): %s", resp.Error)
		}
		if resp.FrameID != "42" {
			log.Fatalf("FAIL: expected frame_id=42, got %s", resp.FrameID)
		}
		if resp.DeviceID != "integration-test" {
			log.Fatalf("FAIL: expected device_id=integration-test, got %s", resp.DeviceID)
		}
	case <-ctx.Done():
		log.Fatal("FAIL: timeout waiting for result")
	}

	// 7. Check gateway status
	status, err := client.GetStatus(ctx, &pb.Empty{})
	if err != nil {
		log.Fatalf("GetStatus: %v", err)
	}
	log.Printf("Gateway status: alive=%v ready=%v frames_processed=%d avg_latency=%.1fms",
		status.Alive, status.Ready, status.FramesProcessed, status.AvgLatencyMs)

	if !status.Alive || !status.Ready {
		log.Fatal("FAIL: gateway not healthy")
	}
	if status.FramesProcessed < 1 {
		log.Fatal("FAIL: no frames processed")
	}

	fmt.Println("\nPASS: integration test succeeded")
}
