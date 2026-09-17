import { ChevronRight, FolderOpen, Monitor, PlusCircle, SquareTerminal } from 'lucide-react';
import type { Session } from '../../../../electron/contracts/sessions';

export default function HomePage({
  sessions,
  onNewTerminal,
  onNewSsh,
  onNewRdp,
  onOpenSessions,
}: {
  sessions: Session[];
  favorites: Session[];
  onNewTerminal: () => void;
  onNewSsh: () => void;
  onNewRdp: () => void;
  onConnect: (session: Session) => void;
  onOpenSessions: () => void;
}) {
  return (
    <div className="welcome-page">
      <section className="welcome-copy">
        <img className="welcome-brand-image" src="/branding/morixterm-home-brand-v2.png" alt="MoriXterm"/>
        <h1>Remote sessions,<br/>made elegant.</h1>
        <p>SSH shells, RDP desktops, and file transfers —<br/>all in one focused workspace.</p>
        <div className="welcome-actions">
          <button className="welcome-primary" onClick={onNewSsh}><PlusCircle size={18}/> New Session</button>
          <button className="welcome-hint" onClick={onOpenSessions}>{sessions.length} saved session{sessions.length === 1 ? '' : 's'} · browse sessions</button>
        </div>
        <div className="protocol-pills"><span>SSH</span><span>RDP</span><span>SFTP / SCP</span></div>
      </section>
      <section className="welcome-stage">
        <div className="welcome-terminal-preview">
          <div className="preview-head"><span className="preview-dots"><i/><i/><i/></span><small>session · ssh</small><b>CONNECTED</b></div>
          <pre><strong>mori</strong><em>xterm</em><span>  ·  connect · manage · explore</span>{'\n'}<b>➜  </b>ssh <mark>user@server</mark>{'\n'}<i>✔  shell ready  ·  files sidebar open</i></pre>
        </div>
        <button className="welcome-feature" onClick={onNewTerminal}><span><SquareTerminal size={18}/></span><div><strong>Interactive shell</strong><small>Themes, search, and multi-tab terminals</small></div></button>
        <button className="welcome-feature" onClick={onNewRdp}><span><Monitor size={18}/></span><div><strong>Remote desktop</strong><small>Launch RDP sessions beside your shells</small></div></button>
        <button className="welcome-feature" onClick={onOpenSessions}><span><FolderOpen size={18}/></span><div><strong>File browser</strong><small>Browse, upload, copy, and chmod remotely</small></div><ChevronRight className="welcome-feature-arrow" size={18}/></button>
      </section>
    </div>
  );
}
