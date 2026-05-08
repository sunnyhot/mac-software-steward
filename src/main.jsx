import React from 'react';
import { createRoot } from 'react-dom/client';
import {
  AlertTriangle,
  AppWindow,
  CheckCircle2,
  ChevronRight,
  ExternalLink,
  Loader2,
  Package,
  Play,
  RefreshCw,
  Search,
  Settings2,
  ShieldCheck,
  Terminal,
  Zap
} from 'lucide-react';
import './styles.css';

const tabs = [
  { id: 'updates', label: '可升级' },
  { id: 'brew', label: 'Homebrew' },
  { id: 'apps', label: '应用程序' },
  { id: 'mas', label: 'App Store' },
  { id: 'jobs', label: '任务日志' }
];

function App() {
  const [activeTab, setActiveTab] = React.useState('updates');
  const [scan, setScan] = React.useState(null);
  const [loading, setLoading] = React.useState(false);
  const [error, setError] = React.useState('');
  const [includeGreedy, setIncludeGreedy] = React.useState(true);
  const [runBrewUpdate, setRunBrewUpdate] = React.useState(true);
  const [jobs, setJobs] = React.useState([]);
  const [activeJobId, setActiveJobId] = React.useState('');
  const [query, setQuery] = React.useState('');

  const activeJob = jobs.find((job) => job.id === activeJobId) ?? jobs[0];
  const updates = React.useMemo(() => collectUpdates(scan), [scan]);

  React.useEffect(() => {
    void refreshJobs();
    void runScan();
  }, []);

  React.useEffect(() => {
    if (!activeJob || !['queued', 'running'].includes(activeJob.status)) return undefined;
    const timer = window.setInterval(() => {
      void refreshJob(activeJob.id);
    }, 1_200);
    return () => window.clearInterval(timer);
  }, [activeJob?.id, activeJob?.status]);

  async function runScan() {
    setLoading(true);
    setError('');
    try {
      const result = await api(`/api/scan?greedy=${includeGreedy ? '1' : '0'}`);
      setScan(result);
    } catch (requestError) {
      setError(requestError.message);
    } finally {
      setLoading(false);
    }
  }

  async function refreshJobs() {
    try {
      const result = await api('/api/jobs');
      setJobs(result.jobs ?? []);
      if (!activeJobId && result.jobs?.length) setActiveJobId(result.jobs[0].id);
    } catch {
      // Job history is a convenience panel; scan errors are shown elsewhere.
    }
  }

  async function refreshJob(id) {
    const job = await api(`/api/jobs/${id}`);
    setJobs((current) => upsertJob(current, job));
  }

  async function upgradeOne(item) {
    setError('');
    try {
      const body = item.manager === 'mas'
        ? { manager: 'mas', appId: item.appId, name: item.name }
        : { manager: 'brew', kind: item.kind, name: item.name, greedy: includeGreedy };
      const job = await api('/api/upgrade', { method: 'POST', body });
      setJobs((current) => upsertJob(current, job));
      setActiveJobId(job.id);
      setActiveTab('jobs');
    } catch (requestError) {
      setError(requestError.message);
    }
  }

  async function upgradeAll() {
    setError('');
    try {
      const body = {
        brewFormulae: scan?.brew?.formulae?.some((item) => item.upgradeable),
        brewCasks: scan?.brew?.casks?.some((item) => item.upgradeable),
        mas: scan?.mas?.apps?.some((item) => item.upgradeable),
        greedy: includeGreedy,
        runBrewUpdate
      };
      const job = await api('/api/upgrade-all', { method: 'POST', body });
      setJobs((current) => upsertJob(current, job));
      setActiveJobId(job.id);
      setActiveTab('jobs');
    } catch (requestError) {
      setError(requestError.message);
    }
  }

  async function revealApp(appPath) {
    setError('');
    try {
      const job = await api('/api/reveal', { method: 'POST', body: { path: appPath } });
      setJobs((current) => upsertJob(current, job));
      setActiveJobId(job.id);
    } catch (requestError) {
      setError(requestError.message);
    }
  }

  return (
    <main className="shell">
      <section className="topbar" aria-label="概览">
        <div>
          <p className="eyebrow">LOCAL MAC SOFTWARE STEWARD</p>
          <h1>Mac 软件管家</h1>
          <p className="intro">
            扫描本机应用、Homebrew formula/cask 和可选的 Mac App Store 应用，集中处理可升级项。
          </p>
        </div>
        <div className="actions">
          <Toggle
            checked={includeGreedy}
            onChange={setIncludeGreedy}
            label="包含 greedy cask"
          />
          <button className="button secondary" onClick={runScan} disabled={loading}>
            {loading ? <Loader2 className="spin" size={18} /> : <RefreshCw size={18} />}
            扫描
          </button>
          <button className="button primary" onClick={upgradeAll} disabled={!updates.length || hasRunningJob(jobs)}>
            <Zap size={18} />
            一键升级
          </button>
        </div>
      </section>

      {error ? (
        <section className="banner danger" role="alert">
          <AlertTriangle size={18} />
          <span>{error}</span>
        </section>
      ) : null}

      <section className="metrics" aria-label="扫描统计">
        <Metric icon={<AppWindow size={20} />} label="应用程序" value={scan?.summary?.applications ?? '-'} />
        <Metric icon={<Package size={20} />} label="Brew Formula" value={scan?.summary?.brewFormulae ?? '-'} />
        <Metric icon={<Settings2 size={20} />} label="Brew Cask" value={scan?.summary?.brewCasks ?? '-'} />
        <Metric icon={<ShieldCheck size={20} />} label="可操作升级" value={scan?.summary?.actionable ?? '-'} tone={updates.length ? 'warn' : 'ok'} />
      </section>

      <section className="toolbar" aria-label="视图切换">
        <div className="tabs" role="tablist" aria-label="软件列表">
          {tabs.map((tab) => (
            <button
              key={tab.id}
              className={activeTab === tab.id ? 'tab active' : 'tab'}
              onClick={() => setActiveTab(tab.id)}
              role="tab"
              aria-selected={activeTab === tab.id}
            >
              {tab.label}
            </button>
          ))}
        </div>
        <label className="search">
          <Search size={17} />
          <input
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="搜索名称、版本、路径"
            aria-label="搜索软件"
          />
        </label>
      </section>

      {activeTab === 'updates' ? (
        <UpdatesPanel
          updates={filterRows(updates, query)}
          loading={loading}
          onUpgrade={upgradeOne}
          runBrewUpdate={runBrewUpdate}
          setRunBrewUpdate={setRunBrewUpdate}
        />
      ) : null}

      {activeTab === 'brew' ? (
        <BrewPanel scan={scan} query={query} onUpgrade={upgradeOne} />
      ) : null}

      {activeTab === 'apps' ? (
        <ApplicationsPanel scan={scan} query={query} onReveal={revealApp} />
      ) : null}

      {activeTab === 'mas' ? (
        <MasPanel scan={scan} query={query} onUpgrade={upgradeOne} />
      ) : null}

      {activeTab === 'jobs' ? (
        <JobsPanel jobs={jobs} activeJob={activeJob} setActiveJobId={setActiveJobId} onRefresh={refreshJobs} />
      ) : null}
    </main>
  );
}

function Metric({ icon, label, value, tone = '' }) {
  return (
    <div className={`metric ${tone}`}>
      <div className="metric-icon">{icon}</div>
      <div>
        <span>{label}</span>
        <strong>{value}</strong>
      </div>
    </div>
  );
}

function Toggle({ checked, onChange, label }) {
  return (
    <label className="toggle">
      <input
        type="checkbox"
        checked={checked}
        onChange={(event) => onChange(event.target.checked)}
      />
      <span aria-hidden="true" />
      {label}
    </label>
  );
}

function UpdatesPanel({ updates, loading, onUpgrade, runBrewUpdate, setRunBrewUpdate }) {
  return (
    <section className="panel">
      <div className="panel-head">
        <div>
          <h2>可升级软件</h2>
          <p>Homebrew 与 Mac App Store 支持自动执行升级；普通 `.app` 会显示在应用列表中供手动处理。</p>
        </div>
        <Toggle checked={runBrewUpdate} onChange={setRunBrewUpdate} label="一键升级前先 brew update" />
      </div>
      {loading ? <EmptyState icon={<Loader2 className="spin" />} title="正在扫描本机软件" text="system_profiler 与 brew outdated 可能需要一点时间。" /> : null}
      {!loading && updates.length === 0 ? <EmptyState icon={<CheckCircle2 />} title="没有发现可操作升级" text="如果需要包含自动更新类 cask，请打开 greedy cask 后重新扫描。" /> : null}
      <div className="rows">
        {updates.map((item) => (
          <PackageRow key={item.id} item={item} onUpgrade={() => onUpgrade(item)} />
        ))}
      </div>
    </section>
  );
}

function BrewPanel({ scan, query, onUpgrade }) {
  const formulae = filterRows(scan?.brew?.formulae ?? [], query);
  const casks = filterRows(scan?.brew?.casks ?? [], query);

  return (
    <section className="panel">
      <div className="panel-head">
        <div>
          <h2>Homebrew</h2>
          <p>{scan?.brew?.available ? `${scan.brew.version} · ${scan.brew.prefix}` : '未检测到 Homebrew'}</p>
        </div>
      </div>
      {scan?.brew?.error ? <InlineWarning text={scan.brew.error} /> : null}
      <h3>Formula</h3>
      <div className="rows compact">
        {formulae.map((item) => <PackageRow key={item.id} item={item} onUpgrade={() => onUpgrade(item)} />)}
      </div>
      <h3>Cask</h3>
      <div className="rows compact">
        {casks.map((item) => <PackageRow key={item.id} item={item} onUpgrade={() => onUpgrade(item)} />)}
      </div>
    </section>
  );
}

function ApplicationsPanel({ scan, query, onReveal }) {
  const apps = filterRows(scan?.applications?.items ?? [], query);

  return (
    <section className="panel">
      <div className="panel-head">
        <div>
          <h2>应用程序</h2>
          <p>来自 system_profiler，覆盖 `/Applications`、用户应用目录与系统应用。</p>
        </div>
      </div>
      {scan?.applications?.error ? <InlineWarning text={scan.applications.error} /> : null}
      <div className="app-table" role="table" aria-label="应用程序">
        <div className="app-row header" role="row">
          <span>名称</span>
          <span>版本</span>
          <span>来源</span>
          <span>升级能力</span>
          <span>位置</span>
        </div>
        {apps.map((app) => (
          <div className="app-row" role="row" key={app.id}>
            <span className="strong">{app.name}</span>
            <span>{app.version || '-'}</span>
            <span>{app.source || '-'}</span>
            <span><StatusPill app={app} /></span>
            <span className="path-cell">
              <button className="link-button" onClick={() => onReveal(app.path)}>
                <ExternalLink size={15} />
                Finder
              </button>
              <small title={app.path}>{app.path}</small>
            </span>
          </div>
        ))}
      </div>
    </section>
  );
}

function MasPanel({ scan, query, onUpgrade }) {
  const apps = filterRows(scan?.mas?.apps ?? [], query);

  return (
    <section className="panel">
      <div className="panel-head">
        <div>
          <h2>Mac App Store</h2>
          <p>{scan?.mas?.available ? '通过 mas CLI 扫描与升级' : '未检测到 mas CLI'}</p>
        </div>
      </div>
      {scan?.mas?.error ? <InlineWarning text={scan.mas.error} /> : null}
      <div className="rows">
        {apps.map((item) => <PackageRow key={item.id} item={item} onUpgrade={() => onUpgrade(item)} />)}
      </div>
    </section>
  );
}

function JobsPanel({ jobs, activeJob, setActiveJobId, onRefresh }) {
  return (
    <section className="panel split">
      <div className="job-list" aria-label="任务">
        <div className="panel-head small">
          <h2>任务</h2>
          <button className="icon-button" onClick={onRefresh} aria-label="刷新任务">
            <RefreshCw size={17} />
          </button>
        </div>
        {jobs.length === 0 ? <p className="muted">暂无升级任务。</p> : null}
        {jobs.map((job) => (
          <button
            className={activeJob?.id === job.id ? 'job-item active' : 'job-item'}
            key={job.id}
            onClick={() => setActiveJobId(job.id)}
          >
            <span>{job.label}</span>
            <StatusText status={job.status} />
          </button>
        ))}
      </div>
      <div className="terminal-panel">
        <div className="terminal-head">
          <Terminal size={18} />
          <span>{activeJob?.label ?? '任务日志'}</span>
          {activeJob ? <StatusText status={activeJob.status} /> : null}
        </div>
        <pre className="log" aria-live="polite">
          {activeJob?.log?.map((entry, index) => `[${entry.stream}] ${entry.text}`).join('\n') || '等待任务输出...'}
        </pre>
      </div>
    </section>
  );
}

function PackageRow({ item, onUpgrade }) {
  const title = item.manager === 'mas' ? item.name : item.name;
  const subtitle = item.manager === 'brew'
    ? `${item.kind} · ${item.installedVersion || '-'}${item.currentVersion ? ` → ${item.currentVersion}` : ''}`
    : `App Store · ${item.installedVersion || '-'}${item.currentVersion ? ` → ${item.currentVersion}` : ''}`;

  return (
    <article className={item.outdated ? 'package-row outdated' : 'package-row'}>
      <div className="package-main">
        <div className="package-icon">
          {item.manager === 'brew' ? <Package size={20} /> : <AppWindow size={20} />}
        </div>
        <div>
          <h3>{title}</h3>
          <p>{subtitle}</p>
        </div>
      </div>
      <div className="package-actions">
        {item.autoUpdates ? <span className="badge neutral">auto_updates</span> : null}
        {item.pinned ? <span className="badge danger">pinned</span> : null}
        {item.outdated ? <span className="badge warn">可升级</span> : <span className="badge ok">已最新</span>}
        <button className="button row-action" disabled={!item.upgradeable} onClick={onUpgrade}>
          <Play size={16} />
          升级
        </button>
      </div>
    </article>
  );
}

function StatusPill({ app }) {
  if (app.managedBy === 'brew-cask') {
    return <span className={app.updateState === 'outdated' ? 'badge warn' : 'badge ok'}>Brew Cask</span>;
  }
  if (app.managedBy === 'mas') {
    return <span className={app.updateState === 'outdated' ? 'badge warn' : 'badge ok'}>App Store</span>;
  }
  return <span className="badge neutral">手动</span>;
}

function StatusText({ status }) {
  const label = {
    queued: '排队',
    running: '运行中',
    succeeded: '完成',
    failed: '失败'
  }[status] || status;
  return <span className={`status ${status}`}>{label}</span>;
}

function InlineWarning({ text }) {
  return (
    <div className="inline-warning">
      <AlertTriangle size={17} />
      <span>{text}</span>
    </div>
  );
}

function EmptyState({ icon, title, text }) {
  return (
    <div className="empty">
      <div className="empty-icon">{icon}</div>
      <h2>{title}</h2>
      <p>{text}</p>
    </div>
  );
}

async function api(url, options = {}) {
  const response = await fetch(url, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      ...(options.headers ?? {})
    },
    body: options.body ? JSON.stringify(options.body) : undefined
  });
  const json = await response.json();
  if (!response.ok) throw new Error(json.error || response.statusText);
  return json;
}

function collectUpdates(scan) {
  if (!scan) return [];
  return [
    ...(scan.brew?.formulae ?? []),
    ...(scan.brew?.casks ?? []),
    ...(scan.mas?.apps ?? [])
  ].filter((item) => item.outdated);
}

function filterRows(rows, query) {
  const needle = query.trim().toLowerCase();
  if (!needle) return rows;
  return rows.filter((row) => JSON.stringify(row).toLowerCase().includes(needle));
}

function upsertJob(jobs, job) {
  const next = jobs.filter((item) => item.id !== job.id);
  return [job, ...next].sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
}

function hasRunningJob(jobs) {
  return jobs.some((job) => ['queued', 'running'].includes(job.status));
}

createRoot(document.getElementById('root')).render(<App />);
