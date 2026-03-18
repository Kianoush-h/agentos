#!/usr/bin/env node
//
// AgentOS Dashboard Server
// Lightweight HTTP server — no external dependencies, Node.js built-ins only.
// Runs on port 18789, serves the web UI and a small REST API.
//
'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');
const { execFile, spawn } = require('child_process');

const PORT = parseInt(process.env.DASHBOARD_PORT || '18789', 10);
const PUBLIC_DIR = path.join(__dirname, 'public');
const AGENT_NAME = process.env.AGENT_NAME || 'Atlas';
const LOG_LINES = 100;

// ── Helpers ────────────────────────────────────────────────────────

function json(res, status, obj) {
    const body = JSON.stringify(obj);
    res.writeHead(status, {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body),
    });
    res.end(body);
}

function readBody(req) {
    return new Promise((resolve, reject) => {
        let data = '';
        req.on('data', chunk => { data += chunk; });
        req.on('end', () => resolve(data));
        req.on('error', reject);
    });
}

function run(cmd, args) {
    return new Promise((resolve) => {
        execFile(cmd, args, { timeout: 5000 }, (err, stdout, stderr) => {
            resolve({ ok: !err, stdout: stdout || '', stderr: stderr || '', code: err?.code });
        });
    });
}

// ── API handlers ───────────────────────────────────────────────────

async function getStatus(res) {
    const [gateway, broker, claude] = await Promise.all([
        run('systemctl', ['is-active', 'agentos-gateway']),
        run('systemctl', ['is-active', 'agentos-broker']),
        run('claude', ['--version']),
    ]);

    json(res, 200, {
        agent_name: AGENT_NAME,
        services: {
            gateway: gateway.stdout.trim(),
            broker: broker.stdout.trim(),
        },
        claude_version: claude.stdout.trim() || 'unknown',
        uptime: process.uptime(),
    });
}

async function getLogs(res) {
    const result = await run('journalctl', [
        '-u', 'agentos-gateway',
        '-u', 'agentos-broker',
        '-n', String(LOG_LINES),
        '--no-pager',
        '--output=short-iso',
    ]);

    json(res, 200, {
        lines: result.stdout.trim().split('\n').filter(Boolean),
    });
}

async function postChat(req, res) {
    let body;
    try {
        body = JSON.parse(await readBody(req));
    } catch {
        return json(res, 400, { error: 'Invalid JSON' });
    }

    const prompt = (body.prompt || '').trim();
    if (!prompt) {
        return json(res, 400, { error: 'prompt is required' });
    }

    // Stream response back as newline-delimited JSON chunks
    res.writeHead(200, {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
    });

    const child = spawn('claude', ['-p', prompt, '--dangerously-skip-permissions'], {
        env: { ...process.env },
        timeout: 120000,
    });

    child.stdout.on('data', chunk => {
        res.write(`data: ${JSON.stringify({ text: chunk.toString() })}\n\n`);
    });

    child.stderr.on('data', chunk => {
        res.write(`data: ${JSON.stringify({ error: chunk.toString() })}\n\n`);
    });

    child.on('close', code => {
        res.write(`data: ${JSON.stringify({ done: true, code })}\n\n`);
        res.end();
    });

    req.on('close', () => child.kill());
}

// ── Static file server ─────────────────────────────────────────────

const MIME = {
    '.html': 'text/html; charset=utf-8',
    '.js':   'application/javascript',
    '.css':  'text/css',
    '.png':  'image/png',
    '.ico':  'image/x-icon',
    '.svg':  'image/svg+xml',
};

function serveStatic(req, res) {
    const urlPath = req.url === '/' ? '/index.html' : req.url;
    const filePath = path.join(PUBLIC_DIR, path.normalize(urlPath));

    // Prevent directory traversal
    if (!filePath.startsWith(PUBLIC_DIR)) {
        res.writeHead(403);
        return res.end('Forbidden');
    }

    fs.readFile(filePath, (err, data) => {
        if (err) {
            res.writeHead(404);
            return res.end('Not found');
        }
        const ext = path.extname(filePath);
        res.writeHead(200, { 'Content-Type': MIME[ext] || 'application/octet-stream' });
        res.end(data);
    });
}

// ── Router ─────────────────────────────────────────────────────────

const server = http.createServer(async (req, res) => {
    res.setHeader('X-Content-Type-Options', 'nosniff');

    try {
        if (req.method === 'GET'  && req.url === '/api/status') return await getStatus(res);
        if (req.method === 'GET'  && req.url === '/api/logs')   return await getLogs(res);
        if (req.method === 'POST' && req.url === '/api/chat')   return await postChat(req, res);
        if (req.method === 'GET')                               return serveStatic(req, res);

        res.writeHead(405);
        res.end('Method Not Allowed');
    } catch (err) {
        console.error('[dashboard] unhandled error:', err);
        json(res, 500, { error: 'Internal server error' });
    }
});

server.listen(PORT, '127.0.0.1', () => {
    console.log(`[AgentOS Dashboard] listening on http://127.0.0.1:${PORT}`);
});

process.on('SIGTERM', () => { server.close(); process.exit(0); });
process.on('SIGINT',  () => { server.close(); process.exit(0); });
