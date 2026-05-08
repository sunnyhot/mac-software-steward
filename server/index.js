import express from 'express';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { scanAll } from './scanners.js';
import { createUpgradeJob, getJob, listJobs, revealInFinder } from './jobs.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, '..');
const app = express();
const port = Number(process.env.PORT || 4317);
const host = process.env.HOST || '127.0.0.1';

app.use(express.json({ limit: '256kb' }));

app.get('/api/health', (_request, response) => {
  response.json({
    ok: true,
    platform: process.platform,
    node: process.version,
    pid: process.pid
  });
});

app.get('/api/scan', async (request, response) => {
  try {
    const includeGreedy = request.query.greedy !== '0';
    const result = await scanAll({ includeGreedy });
    response.json(result);
  } catch (error) {
    response.status(500).json({
      error: error.message
    });
  }
});

app.get('/api/jobs', (_request, response) => {
  response.json({
    jobs: listJobs()
  });
});

app.get('/api/jobs/:id', (request, response) => {
  const job = getJob(request.params.id);
  if (!job) {
    response.status(404).json({ error: 'Job not found.' });
    return;
  }
  response.json(job);
});

app.post('/api/upgrade', async (request, response) => {
  try {
    const job = await createUpgradeJob({
      ...request.body,
      mode: 'one'
    });
    response.status(202).json(job);
  } catch (error) {
    response.status(400).json({ error: error.message });
  }
});

app.post('/api/upgrade-all', async (request, response) => {
  try {
    const job = await createUpgradeJob({
      ...request.body,
      mode: 'all',
      label: '一键升级可管理软件'
    });
    response.status(202).json(job);
  } catch (error) {
    response.status(400).json({ error: error.message });
  }
});

app.post('/api/reveal', async (request, response) => {
  try {
    const job = await revealInFinder(request.body.path);
    response.status(202).json(job);
  } catch (error) {
    response.status(400).json({ error: error.message });
  }
});

if (process.env.NODE_ENV === 'production') {
  const distDir = path.join(rootDir, 'dist');
  app.use(express.static(distDir));
  app.use((request, response, next) => {
    if (request.method !== 'GET' || request.path.startsWith('/api/')) {
      next();
      return;
    }
    response.sendFile(path.join(distDir, 'index.html'));
  });
}

app.listen(port, host, () => {
  console.log(`Mac 软件管家 API listening on http://${host}:${port}`);
});
