#!/usr/bin/env node
/**
 * OpenClaw Inter-Instance Communication Bridge
 *
 * Provides:
 * - Authenticated RPC for task delegation
 * - Signed message verification
 * - Rate limiting to prevent delegation loops
 * - Audit logging for all inter-instance messages
 * - Shared context store gatekeeper
 */

const http = require('http');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

// Configuration from environment
const CONFIG = {
  port: parseInt(process.env.BRIDGE_PORT || '18800'),
  sharedContextPath: process.env.SHARED_CONTEXT_PATH || '/var/lib/openclaw/shared-context',
  auditLogPath: process.env.AUDIT_LOG_PATH || '/var/log/openclaw/bridge-audit.log',
  maxRequestsPerMinute: parseInt(process.env.RATE_LIMIT || '60'),
  maxDelegationDepth: parseInt(process.env.MAX_DELEGATION_DEPTH || '5'),
};

// Load shared secret for authentication
let sharedSecret;
try {
  sharedSecret = fs.readFileSync('/run/secrets/bridge-shared-secret', 'utf8').trim();
} catch (err) {
  console.error('Failed to load bridge shared secret:', err.message);
  process.exit(1);
}

// Rate limiting state
const requestCounts = new Map();

// Audit log stream
const auditLog = fs.createWriteStream(CONFIG.auditLogPath, { flags: 'a' });

function log(level, message, data = {}) {
  const entry = {
    timestamp: new Date().toISOString(),
    level,
    message,
    ...data
  };
  auditLog.write(JSON.stringify(entry) + '\n');
  console.log(`[${level}] ${message}`, data);
}

// Verify HMAC signature
function verifySignature(instanceId, timestamp, payload, signature) {
  const message = `${instanceId}:${timestamp}:${JSON.stringify(payload)}`;
  const expected = crypto.createHmac('sha256', sharedSecret)
    .update(message)
    .digest('hex');
  return crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(expected));
}

// Rate limiting check
function checkRateLimit(instanceId) {
  const now = Date.now();
  const windowStart = now - 60000; // 1 minute window

  if (!requestCounts.has(instanceId)) {
    requestCounts.set(instanceId, []);
  }

  const requests = requestCounts.get(instanceId);
  const recentRequests = requests.filter(t => t > windowStart);
  requestCounts.set(instanceId, recentRequests);

  if (recentRequests.length >= CONFIG.maxRequestsPerMinute) {
    return false;
  }

  recentRequests.push(now);
  return true;
}

// Handle task delegation request
async function handleDelegation(req, res, body) {
  const { fromInstance, toInstance, task, delegationChain = [] } = body;

  // Check delegation depth
  if (delegationChain.length >= CONFIG.maxDelegationDepth) {
    log('warn', 'Delegation depth exceeded', { fromInstance, chain: delegationChain });
    res.writeHead(400);
    res.end(JSON.stringify({ error: 'Maximum delegation depth exceeded' }));
    return;
  }

  // Prevent delegation loops
  if (delegationChain.includes(toInstance)) {
    log('warn', 'Delegation loop detected', { fromInstance, toInstance, chain: delegationChain });
    res.writeHead(400);
    res.end(JSON.stringify({ error: 'Delegation loop detected' }));
    return;
  }

  log('info', 'Task delegation', { fromInstance, toInstance, taskType: task?.type });

  // Queue the delegation for the target instance
  const delegationId = crypto.randomUUID();
  const delegation = {
    id: delegationId,
    from: fromInstance,
    to: toInstance,
    task,
    chain: [...delegationChain, fromInstance],
    timestamp: Date.now()
  };

  // Store delegation in shared context
  const delegationPath = path.join(CONFIG.sharedContextPath, 'delegations', `${delegationId}.json`);
  fs.mkdirSync(path.dirname(delegationPath), { recursive: true });
  fs.writeFileSync(delegationPath, JSON.stringify(delegation, null, 2));

  res.writeHead(200);
  res.end(JSON.stringify({ delegationId, status: 'queued' }));
}

// Handle context update request
async function handleContextUpdate(req, res, body) {
  const { instanceId, contextKey, value, signature: valueSignature } = body;

  // Validate context key format
  if (!/^[a-zA-Z0-9_-]+$/.test(contextKey)) {
    res.writeHead(400);
    res.end(JSON.stringify({ error: 'Invalid context key format' }));
    return;
  }

  log('info', 'Context update', { instanceId, contextKey });

  // Store context update with metadata
  const contextPath = path.join(CONFIG.sharedContextPath, 'context', `${contextKey}.json`);
  fs.mkdirSync(path.dirname(contextPath), { recursive: true });

  const contextData = {
    key: contextKey,
    value,
    updatedBy: instanceId,
    updatedAt: new Date().toISOString(),
    signature: valueSignature
  };

  fs.writeFileSync(contextPath, JSON.stringify(contextData, null, 2));

  res.writeHead(200);
  res.end(JSON.stringify({ status: 'updated', key: contextKey }));
}

// Parse request body
function parseBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      try {
        resolve(JSON.parse(body));
      } catch (err) {
        reject(err);
      }
    });
    req.on('error', reject);
  });
}

// Main request handler
const server = http.createServer(async (req, res) => {
  // Only allow POST requests
  if (req.method !== 'POST') {
    res.writeHead(405);
    res.end(JSON.stringify({ error: 'Method not allowed' }));
    return;
  }

  let body;
  try {
    body = await parseBody(req);
  } catch (err) {
    res.writeHead(400);
    res.end(JSON.stringify({ error: 'Invalid JSON' }));
    return;
  }

  // Authenticate request
  const { instanceId, timestamp, signature, payload } = body;

  if (!instanceId || !timestamp || !signature || !payload) {
    res.writeHead(400);
    res.end(JSON.stringify({ error: 'Missing required fields' }));
    return;
  }

  // Check timestamp (prevent replay attacks)
  const requestTime = parseInt(timestamp);
  const now = Date.now();
  if (Math.abs(now - requestTime) > 30000) { // 30 second window
    log('warn', 'Request timestamp out of range', { instanceId, drift: now - requestTime });
    res.writeHead(401);
    res.end(JSON.stringify({ error: 'Request timestamp out of range' }));
    return;
  }

  // Verify signature
  if (!verifySignature(instanceId, timestamp, payload, signature)) {
    log('warn', 'Invalid signature', { instanceId });
    res.writeHead(401);
    res.end(JSON.stringify({ error: 'Invalid signature' }));
    return;
  }

  // Check rate limit
  if (!checkRateLimit(instanceId)) {
    log('warn', 'Rate limit exceeded', { instanceId });
    res.writeHead(429);
    res.end(JSON.stringify({ error: 'Rate limit exceeded' }));
    return;
  }

  // Route request
  const url = new URL(req.url, `http://${req.headers.host}`);

  switch (url.pathname) {
    case '/delegate':
      await handleDelegation(req, res, payload);
      break;
    case '/context/update':
      await handleContextUpdate(req, res, payload);
      break;
    case '/health':
      res.writeHead(200);
      res.end(JSON.stringify({ status: 'healthy' }));
      break;
    default:
      res.writeHead(404);
      res.end(JSON.stringify({ error: 'Not found' }));
  }
});

// Start server
server.listen(CONFIG.port, '127.0.0.1', () => {
  log('info', `Bridge service started on port ${CONFIG.port}`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  log('info', 'Shutting down bridge service');
  server.close(() => {
    auditLog.end();
    process.exit(0);
  });
});
