// Quick WebSocket test: connects to gateway /ws/results, waits for one message.
package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/gorilla/websocket"
)

func main() {
	wsURL := flag.String("url", "ws://gateway:8080/ws/results", "WebSocket URL")
	timeout := flag.Duration("timeout", 60*time.Second, "max wait time")
	flag.Parse()

	log.Printf("Connecting to %s", *wsURL)
	c, _, err := websocket.DefaultDialer.Dial(*wsURL, nil)
	if err != nil {
		log.Fatalf("WebSocket dial: %v", err)
	}
	defer c.Close()
	log.Println("Connected, waiting for message...")

	done := make(chan struct{})
	go func() {
		defer close(done)
		_, msg, err := c.ReadMessage()
		if err != nil {
			log.Printf("Read error: %v", err)
			os.Exit(1)
		}
		fmt.Printf("Received: %s\n", msg)
	}()

	select {
	case <-done:
		fmt.Println("\nPASS: WebSocket received result")
	case <-time.After(*timeout):
		log.Fatal("FAIL: timeout waiting for WebSocket message")
	}
}
