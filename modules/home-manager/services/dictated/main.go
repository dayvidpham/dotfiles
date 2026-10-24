// Command dictated is the warm Parakeet transcription daemon.
//
// It loads the sherpa-onnx recognizer once and answers HTTP POSTs over a Unix
// socket. Audio arrives as a canonical 16 kHz mono PCM16 WAV body, or as raw
// s16le on /transcribe-raw, and is decoded in memory.
package main

/*
#include <stdlib.h>
#include "bridge.h"
*/
import "C"

import (
	"encoding/binary"
	"errors"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"unsafe"
)

// recognizer owns the sherpa-onnx handle and serializes access to it.
type recognizer struct {
	mu     sync.Mutex
	handle unsafe.Pointer
	// The C strings must outlive the recognizer; sherpa keeps the pointers.
	keep []*C.char

	// Silero VAD, when set, splits a recording into speech segments so silence
	// is never decoded.
	vadModel    string
	threshold   float32
	minSilence  float32
	minSpeech   float32
	minSeconds  float64
}

func newRecognizer(modelDir string, threads int) (*recognizer, error) {
	files := []string{"encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx", "tokens.txt"}
	keep := make([]*C.char, 0, len(files)+1)
	for _, name := range files {
		keep = append(keep, C.CString(filepath.Join(modelDir, name)))
	}
	provider := C.CString("cpu")
	keep = append(keep, provider)

	handle := C.dictated_create(keep[0], keep[1], keep[2], keep[3], C.int32_t(threads), provider)
	if handle == nil {
		return nil, errors.New("sherpa-onnx could not create the recognizer")
	}
	return &recognizer{handle: handle, keep: keep}, nil
}

// transcribe decodes one contiguous run of samples. The caller holds the lock.
func (r *recognizer) transcribe(samples []float32) string {
	if len(samples) == 0 {
		return ""
	}
	text := C.dictated_transcribe(r.handle, (*C.float)(unsafe.Pointer(&samples[0])), C.int32_t(len(samples)))
	if text == nil {
		return ""
	}
	defer C.dictated_free_string(text)
	return strings.TrimSpace(C.GoString(text))
}

// decode transcribes the recording, split into speech segments when VAD is on.
func (r *recognizer) decode(samples []float32) string {
	if len(samples) == 0 {
		return ""
	}
	r.mu.Lock()
	defer r.mu.Unlock()

	// Short utterances are decoded whole: splitting them costs punctuation and
	// capitalisation at every boundary, and they are fast anyway.
	if r.vadModel == "" || float64(len(samples))/16000 < r.minSeconds {
		return r.transcribe(samples)
	}

	model := C.CString(r.vadModel)
	defer C.free(unsafe.Pointer(model))
	vad := C.dictated_vad_create(model, C.float(r.threshold), C.float(r.minSilence), C.float(r.minSpeech))
	if vad == nil {
		// Never lose the recording because the detector failed to load.
		return r.transcribe(samples)
	}
	defer C.dictated_vad_destroy(vad)

	const maxSegments = 4096
	pairs := make([]int32, maxSegments*2)
	found := int(C.dictated_vad_split(vad,
		(*C.float)(unsafe.Pointer(&samples[0])), C.int32_t(len(samples)),
		(*C.int32_t)(unsafe.Pointer(&pairs[0])), C.int32_t(maxSegments)))
	if found <= 0 {
		return ""
	}

	parts := make([]string, 0, found)
	for i := 0; i < found; i++ {
		start := int(pairs[i*2])
		n := int(pairs[i*2+1])
		if start < 0 || n <= 0 || start+n > len(samples) {
			continue
		}
		if text := r.transcribe(samples[start : start+n]); text != "" {
			parts = append(parts, text)
		}
	}
	return strings.Join(parts, " ")
}

// raw16 converts s16le mono samples to floats.
func raw16(body []byte) []float32 {
	samples := make([]float32, len(body)>>1)
	for i := range samples {
		samples[i] = float32(int16(binary.LittleEndian.Uint16(body[i*2:]))) / 32768
	}
	return samples
}

// pcm16 reads the data chunk of a RIFF WAV.
func pcm16(body []byte) ([]float32, error) {
	if len(body) < 44 || string(body[0:4]) != "RIFF" {
		return nil, errors.New("not a RIFF WAV")
	}
	for offset := 12; offset+8 <= len(body); {
		id := string(body[offset : offset+4])
		size := int(binary.LittleEndian.Uint32(body[offset+4:]))
		start := offset + 8
		if id == "data" {
			end := start + size
			if end > len(body) {
				end = len(body)
			}
			return raw16(body[start:end]), nil
		}
		offset = start + size + size&1
	}
	return nil, errors.New("no data chunk")
}

type daemon struct {
	rec      *recognizer
	maxBytes int64
}

func (d *daemon) handle(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "not found", http.StatusNotFound)
		return
	}
	body, err := io.ReadAll(io.LimitReader(r.Body, d.maxBytes+1))
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	if int64(len(body)) > d.maxBytes {
		http.Error(w, "recording too large", http.StatusRequestEntityTooLarge)
		return
	}

	var samples []float32
	if r.URL.Path == "/transcribe-raw" {
		samples = raw16(body)
	} else {
		samples, err = pcm16(body)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
	}

	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	_, _ = io.WriteString(w, d.rec.decode(samples))
}

func envInt(key string, fallback int) int {
	if value, err := strconv.Atoi(os.Getenv(key)); err == nil && value > 0 {
		return value
	}
	return fallback
}

func envFloat(key string, fallback float64) float64 {
	if value, err := strconv.ParseFloat(os.Getenv(key), 64); err == nil && value > 0 {
		return value
	}
	return fallback
}

func main() {
	socketPath := os.Getenv("DICTATED_SOCKET")
	modelDir := os.Getenv("DICTATED_MODEL_DIR")
	if socketPath == "" || modelDir == "" {
		log.Fatal("dictated: DICTATED_SOCKET and DICTATED_MODEL_DIR are required")
	}
	threads := envInt("DICTATED_THREADS", 4)
	maxBytes := int64(envInt("DICTATED_MAX_BYTES", 8<<20))

	rec, err := newRecognizer(modelDir, threads)
	if err != nil {
		log.Fatalf("dictated: %v", err)
	}
	rec.vadModel = os.Getenv("DICTATED_VAD_MODEL")
	rec.threshold = float32(envFloat("DICTATED_VAD_THRESHOLD", 0.5))
	rec.minSilence = float32(envFloat("DICTATED_VAD_MIN_SILENCE", 0.6))
	rec.minSpeech = float32(envFloat("DICTATED_VAD_MIN_SPEECH", 0.25))
	rec.minSeconds = envFloat("DICTATED_VAD_MIN_SECONDS", 30)

	if err := os.MkdirAll(filepath.Dir(socketPath), 0o700); err != nil {
		log.Fatalf("dictated: %v", err)
	}
	_ = os.Remove(socketPath)
	listener, err := net.Listen("unix", socketPath)
	if err != nil {
		log.Fatalf("dictated: %v", err)
	}
	if err := os.Chmod(socketPath, 0o600); err != nil {
		log.Fatalf("dictated: %v", err)
	}

	mux := http.NewServeMux()
	d := &daemon{rec: rec, maxBytes: maxBytes}
	mux.HandleFunc("/transcribe", d.handle)
	mux.HandleFunc("/transcribe-raw", d.handle)

	log.Printf("dictated: ready on %s (%d threads, vad=%t)", socketPath, threads, rec.vadModel != "")

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-stop
		_ = listener.Close()
		_ = os.Remove(socketPath)
		os.Exit(0)
	}()

	if err := http.Serve(listener, mux); err != nil {
		log.Fatalf("dictated: %v", err)
	}
}
