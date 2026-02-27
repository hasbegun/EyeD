package store

import (
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
)

// LocalStore implements ObjectStore using the local filesystem.
type LocalStore struct {
	root string
}

// NewLocal creates a local filesystem store rooted at the given directory.
func NewLocal(root string) (*LocalStore, error) {
	if err := os.MkdirAll(root, 0o755); err != nil {
		return nil, fmt.Errorf("create archive root %s: %w", root, err)
	}
	return &LocalStore{root: root}, nil
}

func (s *LocalStore) Put(path string, data []byte) error {
	full := filepath.Join(s.root, path)

	dir := filepath.Dir(full)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return fmt.Errorf("mkdir %s: %w", dir, err)
	}

	// Atomic write: write to .tmp then rename
	tmp := full + ".tmp"
	if err := os.WriteFile(tmp, data, 0o644); err != nil {
		return fmt.Errorf("write %s: %w", tmp, err)
	}
	if err := os.Rename(tmp, full); err != nil {
		os.Remove(tmp)
		return fmt.Errorf("rename %s → %s: %w", tmp, full, err)
	}
	return nil
}

func (s *LocalStore) Delete(path string) error {
	full := filepath.Join(s.root, path)
	return os.Remove(full)
}

func (s *LocalStore) Walk(root string, fn fs.WalkDirFunc) error {
	full := filepath.Join(s.root, root)
	if _, err := os.Stat(full); os.IsNotExist(err) {
		return nil // nothing to walk
	}
	return filepath.WalkDir(full, fn)
}

// Root returns the absolute root path of the store.
func (s *LocalStore) Root() string {
	return s.root
}
