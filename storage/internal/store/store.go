package store

import "io/fs"

// ObjectStore abstracts file storage operations.
// Local filesystem for dev/edge; S3-compatible for cloud (future).
type ObjectStore interface {
	// Put writes data to the given path (relative to store root).
	// Creates parent directories as needed.
	Put(path string, data []byte) error

	// Delete removes the file at the given path.
	Delete(path string) error

	// Walk traverses the directory tree rooted at root, calling fn for each entry.
	Walk(root string, fn fs.WalkDirFunc) error
}
