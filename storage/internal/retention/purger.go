package retention

import (
	"context"
	"fmt"
	"io/fs"
	"log/slog"
	"os"
	"path/filepath"
	"time"

	"github.com/hasbegun/eyed/storage/internal/store"
)

// Purger enforces retention policies by deleting expired data.
type Purger struct {
	store       *store.LocalStore
	rawDays     int
	logger      *slog.Logger
}

// NewPurger creates a retention purger.
// rawDays: delete raw/ directories older than this many days (0 = keep forever).
func NewPurger(s *store.LocalStore, rawDays int, logger *slog.Logger) *Purger {
	return &Purger{store: s, rawDays: rawDays, logger: logger}
}

// Run starts the retention purger loop. It runs once immediately, then daily.
func (p *Purger) Run(ctx context.Context) {
	p.purge()

	ticker := time.NewTicker(24 * time.Hour)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			p.logger.Info("Retention purger stopped")
			return
		case <-ticker.C:
			p.purge()
		}
	}
}

func (p *Purger) purge() {
	if p.rawDays <= 0 {
		p.logger.Debug("Retention disabled (raw_days=0), skipping purge")
		return
	}

	cutoff := time.Now().UTC().AddDate(0, 0, -p.rawDays)
	p.logger.Info("Running retention purge", "cutoff", cutoff.Format("2006-01-02"), "raw_days", p.rawDays)

	rawRoot := filepath.Join(p.store.Root(), "raw")
	if _, err := os.Stat(rawRoot); os.IsNotExist(err) {
		return
	}

	var dirsRemoved int
	var bytesFreed int64

	// Walk top-level date directories under raw/
	entries, err := os.ReadDir(rawRoot)
	if err != nil {
		p.logger.Error("Failed to read raw directory", "error", err)
		return
	}

	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}

		// Parse directory name as date (YYYY-MM-DD)
		dirDate, err := time.Parse("2006-01-02", entry.Name())
		if err != nil {
			continue // skip non-date directories
		}

		if dirDate.Before(cutoff) {
			dirPath := filepath.Join(rawRoot, entry.Name())
			size := dirSize(dirPath)
			if err := os.RemoveAll(dirPath); err != nil {
				p.logger.Error("Failed to remove expired directory",
					"path", dirPath, "error", err)
				continue
			}
			dirsRemoved++
			bytesFreed += size
		}
	}

	if dirsRemoved > 0 {
		p.logger.Info("Retention purge complete",
			"dirs_removed", dirsRemoved,
			"bytes_freed", bytesFreed,
			"mb_freed", fmt.Sprintf("%.1f", float64(bytesFreed)/(1024*1024)),
		)
	} else {
		p.logger.Debug("Retention purge: nothing to remove")
	}
}

// dirSize calculates total size of files in a directory tree.
func dirSize(path string) int64 {
	var total int64
	filepath.WalkDir(path, func(_ string, d fs.DirEntry, _ error) error {
		if !d.IsDir() {
			if info, err := d.Info(); err == nil {
				total += info.Size()
			}
		}
		return nil
	})
	return total
}
