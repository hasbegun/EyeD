package breaker

import (
	"sync"
	"time"
)

// State represents the circuit breaker state.
type State int

const (
	Closed   State = iota // Normal: accepting frames
	Open                  // Tripped: rejecting frames
	HalfOpen              // Probing: allowing one frame to test recovery
)

func (s State) String() string {
	switch s {
	case Closed:
		return "closed"
	case Open:
		return "open"
	case HalfOpen:
		return "half-open"
	default:
		return "unknown"
	}
}

// Breaker is a circuit breaker that tracks iris-engine responsiveness.
//
// It opens (trips) when frames have been sent but no results received
// within the timeout window. It half-opens periodically to probe for recovery.
type Breaker struct {
	mu            sync.Mutex
	state         State
	timeout       time.Duration // How long without results before tripping
	probeInterval time.Duration // How often to probe when open
	lastSent      time.Time     // Last time a frame was sent
	lastResult    time.Time     // Last time a result was received
	lastProbe     time.Time     // Last time we allowed a probe frame
}

// New creates a circuit breaker with the given timeout and probe interval.
func New(timeout, probeInterval time.Duration) *Breaker {
	now := time.Now()
	return &Breaker{
		state:         Closed,
		timeout:       timeout,
		probeInterval: probeInterval,
		lastResult:    now, // Start as if we just got a result (don't trip on startup)
	}
}

// Allow checks whether a frame should be accepted.
// Returns true if the frame should be processed, false if rejected.
func (b *Breaker) Allow() bool {
	b.mu.Lock()
	defer b.mu.Unlock()

	now := time.Now()
	b.evaluate(now)

	switch b.state {
	case Closed:
		b.lastSent = now
		return true
	case HalfOpen:
		b.lastSent = now
		b.lastProbe = now
		b.state = Open // Back to open until we get a result
		return true
	case Open:
		return false
	}
	return false
}

// RecordResult signals that a result was received from iris-engine.
func (b *Breaker) RecordResult() {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.lastResult = time.Now()
	b.state = Closed
}

// State returns the current circuit breaker state.
func (b *Breaker) State() State {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.evaluate(time.Now())
	return b.state
}

// evaluate updates state based on timing (must be called with lock held).
func (b *Breaker) evaluate(now time.Time) {
	switch b.state {
	case Closed:
		// Trip if we've sent frames but got no results within timeout
		if !b.lastSent.IsZero() && b.lastSent.After(b.lastResult) &&
			now.Sub(b.lastSent) > b.timeout {
			b.state = Open
		}
	case Open:
		// Transition to half-open if enough time has passed since last probe
		if now.Sub(b.lastProbe) > b.probeInterval {
			b.state = HalfOpen
		}
	}
}
