import { useEffect, useState } from 'react';

export default function AboutPage({ compact = false }: { compact?: boolean }) {
  const [info, setInfo] = useState<{ version: string; platform: string; electron: string; node: string } | null>(null);

  useEffect(() => {
    void window.mori.appInfo().then(setInfo);
  }, []);

  return (
    <div className={compact ? 'about-modal-content' : 'page about-page'}>
      <img src="/branding/morixterm-logo.svg" alt="MoriXterm" className="about-logo"/>
      {!compact && <h1>MoriXterm</h1>}
      <p className="hero-copy">Modern Remote Terminal & Connection Manager</p>
      <div className="panel about-meta">
        <div><span>Version</span><strong>{info?.version ?? '…'}</strong></div>
        <div><span>Platform</span><strong>{info?.platform ?? '…'}</strong></div>
        <div><span>Electron</span><strong>{info?.electron ?? '…'}</strong></div>
        <div><span>Node</span><strong>{info?.node ?? '…'}</strong></div>
      </div>
      <p className="empty-state">Replace assets/branding logo files with the official MoriXterm artwork when available.</p>
    </div>
  );
}
