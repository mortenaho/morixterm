import { useWorkspace } from '../stores/workspaceStore';
import { useEffect, useState } from 'react';
import { Activity, HardDrive, MemoryStick, Cpu, RefreshCw } from 'lucide-react';
import type { MonitorStats, MonitorTarget } from '../../../electron/contracts/monitor';

function displayPercent(value: number | null): string {
  return value === null ? '—' : `${value}%`;
}

export default function StatusBar({ target }: { target?: MonitorTarget }) {
  const connectionLabel = useWorkspace(state => state.connectionLabel);
  const cols = useWorkspace(state => state.cols);
  const rows = useWorkspace(state => state.rows);
  const [visible, setVisible] = useState(true);
  const [stats, setStats] = useState<MonitorStats | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [updating, setUpdating] = useState(false);
  useEffect(() => {
    let active = true;
    setStats(null);
    setError(null);
    if (!target) return () => { active = false; };
    const update = async () => {
      if (active) setUpdating(true);
      try {
        const result = await window.mori.monitor.stats(target);
        if (!active) return;
        if (result.ok && result.value) {
          setStats(result.value);
          setError(null);
        } else {
          setError(result.message ?? 'Monitoring is unavailable for this session.');
        }
      } catch {
        if (active) setError('Monitoring is unavailable for this session.');
      } finally {
        if (active) setUpdating(false);
      }
    };
    void update();
    const timer = window.setInterval(() => void update(), 3000);
    return () => { active = false; window.clearInterval(timer); };
  }, [target]);

  return (
    <footer className="statusbar">
      <span>{connectionLabel}</span>
      <span>UTF-8</span>
      <span>{cols}×{rows}</span>
      {target && <button className="monitor-toggle" onClick={() => setVisible(value => !value)} title={visible ? 'Hide session monitor' : 'Show session monitor'} aria-label={visible ? 'Hide session monitor' : 'Show session monitor'}><Activity size={13}/>{visible ? 'Monitor' : 'Show monitor'}</button>}
      {visible && target && <section className="monitor-metrics" aria-live="polite">
        <div className="monitor-heading"><span className={`monitor-state ${error ? 'error' : ''}`}/><strong>{stats?.label ?? 'SESSION MONITOR'}</strong>{updating && <RefreshCw className="monitor-refresh" size={11}/>}</div>
        {stats ? <>
          <span title="CPU usage"><Cpu size={13}/><b>CPU</b>{displayPercent(stats.cpu)}</span>
          <span title="Memory usage"><MemoryStick size={13}/><b>RAM</b>{displayPercent(stats.memory)}</span>
          <span title="Root filesystem usage"><HardDrive size={13}/><b>DISK</b>{displayPercent(stats.disk)}</span>
        </> : <small className="monitor-message">{error ?? 'Collecting session metrics…'}</small>}
      </section>}
      <span className="statusbar-brand">Made with care by MoriXterm</span>
    </footer>
  );
}
