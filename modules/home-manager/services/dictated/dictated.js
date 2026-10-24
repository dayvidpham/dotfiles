/**
 * Warm Parakeet transcription daemon.
 *
 * Loads the ONNX recognizer once and answers HTTP POSTs over a Unix socket.
 * Audio arrives as a canonical 16 kHz mono PCM16 WAV body and is decoded in
 * memory; nothing is written to disk.
 */
'use strict'

const http = require('node:http')
const fs = require('node:fs')
const path = require('node:path')

const socketPath = process.env.DICTATED_SOCKET
const modelDir = process.env.DICTATED_MODEL_DIR
const runtime = process.env.DICTATED_RUNTIME
const threads = Number(process.env.DICTATED_THREADS || 4)
const maxBytes = Number(process.env.DICTATED_MAX_BYTES || 8 * 1024 * 1024)

if (!socketPath || !modelDir || !runtime) {
  console.error('dictated: DICTATED_SOCKET, DICTATED_MODEL_DIR and DICTATED_RUNTIME are required')
  process.exit(1)
}

const sherpa = require(runtime)

const recognizer = new sherpa.OfflineRecognizer({
  featConfig: { sampleRate: 16000, featureDim: 80 },
  modelConfig: {
    transducer: {
      encoder: path.join(modelDir, 'encoder.int8.onnx'),
      decoder: path.join(modelDir, 'decoder.int8.onnx'),
      joiner: path.join(modelDir, 'joiner.int8.onnx'),
    },
    tokens: path.join(modelDir, 'tokens.txt'),
    numThreads: threads,
    provider: 'cpu',
    debug: 0,
  },
})

/** s16le mono samples to float. */
function raw16(buffer) {
  const count = buffer.length >> 1
  return Float32Array.from({ length: count }, (_, i) => buffer.readInt16LE(i * 2) / 32768)
}

/** Read the data chunk of a RIFF WAV into float samples. */
function pcm16(wav) {
  const view = new DataView(wav.buffer, wav.byteOffset, wav.byteLength)
  if (view.byteLength < 44 || view.getUint32(0, true) !== 0x46464952) throw new Error('not a RIFF WAV')
  for (let offset = 12; offset + 8 <= view.byteLength;) {
    const id = view.getUint32(offset, true)
    const size = view.getUint32(offset + 4, true)
    const body = offset + 8
    if (id === 0x61746164) {
      const count = Math.max(0, Math.min(size, view.byteLength - body)) >> 1
      return Float32Array.from({ length: count }, (_, i) => view.getInt16(body + i * 2, true) / 32768)
    }
    offset = body + size + (size & 1)
  }
  throw new Error('no data chunk')
}

const server = http.createServer((request, response) => {
  if (request.method !== 'POST' || (request.url !== '/transcribe' && request.url !== '/transcribe-raw')) {
    response.writeHead(404, { 'content-type': 'text/plain' }).end('not found')
    return
  }
  const chunks = []
  let received = 0
  request.on('data', (chunk) => {
    received += chunk.length
    if (received > maxBytes) {
      request.destroy()
      return
    }
    chunks.push(chunk)
  })
  request.on('end', () => {
    try {
      const body = Buffer.concat(chunks)
      const samples = request.url === '/transcribe-raw' ? raw16(body) : pcm16(body)
      const stream = recognizer.createStream()
      stream.acceptWaveform({ sampleRate: 16000, samples })
      recognizer.decode(stream)
      const text = String(recognizer.getResult(stream).text || '').trim()
      response.writeHead(200, { 'content-type': 'text/plain; charset=utf-8' }).end(text)
    } catch (error) {
      response.writeHead(500, { 'content-type': 'text/plain' }).end(String(error.message || error))
    }
  })
})

fs.mkdirSync(path.dirname(socketPath), { recursive: true, mode: 0o700 })
try {
  fs.unlinkSync(socketPath)
} catch {}
server.listen(socketPath, () => {
  fs.chmodSync(socketPath, 0o600)
  console.error(`dictated: ready on ${socketPath} (${threads} threads)`)
})

function shutdown() {
  server.close(() => process.exit(0))
  try {
    fs.unlinkSync(socketPath)
  } catch {}
  setTimeout(() => process.exit(0), 2000).unref()
}
process.on('SIGTERM', shutdown)
process.on('SIGINT', shutdown)
