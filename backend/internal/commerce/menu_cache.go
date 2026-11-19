package commerce

import (
	"crypto/sha256"
	"fmt"
	"net/http"
	"sync"
	"time"
)

type menuResponseCache struct {
	mu    sync.Mutex
	data  []byte
	until time.Time
}

func writeMenu(w http.ResponseWriter, r *http.Request, data []byte) {
	tag := fmt.Sprintf(`"%x"`, sha256.Sum256(data))
	w.Header().Set("ETag", tag)
	w.Header().Set("Cache-Control", "public, max-age=0, s-maxage=10, stale-while-revalidate=10")
	if r.Header.Get("If-None-Match") == tag {
		w.WriteHeader(304)
		return
	}
	_, _ = w.Write(data)
}
