import { useEffect, useState } from 'react';
import { Box, Cpu, Monitor, PackageCheck } from 'lucide-react';

export default function AboutPage({ compact = false }: { compact?: boolean }) {
  const [info, setInfo] = useState<{ version: string; platform: string; electron: string; node: string } | null>(null);

  useEffect(() => {
    void window.mori.appInfo().then(setInfo);
  }, []);

  return (
    <div className={compact ? 'about-modal-content' : 'page about-page'}>
      <section className="about-hero">
        <span className="about-logo-wrap"><img src="/branding/morixterm-logo.svg" alt="Application logo" className="about-logo"/></span>
        <div className="about-hero-copy">
          {!compact && <h1>MoriXterm</h1>}
          <p>Modern remote terminal and connection manager</p>
          <div className="about-protocols" aria-label="Supported connection types"><span>SSH</span><span>RDP</span><span>SFTP</span><span>Terminal</span></div>
        </div>
      </section>
      <div className="about-meta" aria-label="Application information">
        <div><span className="about-meta-icon"><PackageCheck size={16}/></span><span><small>Version</small><strong>{info?.version ?? '…'}</strong></span></div>
        <div><span className="about-meta-icon"><Monitor size={16}/></span><span><small>Platform</small><strong>{formatPlatform(info?.platform)}</strong></span></div>
        <div><span className="about-meta-icon"><Box size={16}/></span><span><small>Electron</small><strong>{info?.electron ?? '…'}</strong></span></div>
        <div><span className="about-meta-icon"><Cpu size={16}/></span><span><small>Node.js</small><strong>{info?.node ?? '…'}</strong></span></div>
      </div>
      <footer className="about-footer"><span className="about-ready-dot"/>Ready for secure remote work</footer>
    </div>
  );
}

function formatPlatform(platform?: string) {
  if (!platform) return '…';
  return ({ win32: 'Windows', darwin: 'macOS', linux: 'Linux' } as Record<string, string>)[platform] ?? platform;
}
