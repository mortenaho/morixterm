import { Activity, Columns2, FolderOpen, Info, LockKeyhole, Plus, Search, Settings, SquareTerminal, Wrench } from 'lucide-react';
import { useWorkspace } from '../stores/workspaceStore';

export default function TitleBar({ onQuickConnect, onNewTerminal, onNewSsh, onSettings, onAbout, onLock }: {
  onQuickConnect: () => void;
  onNewTerminal: () => void;
  onNewSsh: () => void;
  onSettings: () => void;
  onAbout: () => void;
  onLock: () => void;
}) {
  const setPaletteOpen = useWorkspace(state => state.setPaletteOpen);
  const openTab = useWorkspace(state => state.openTab);

  return (
    <header className="titlebar">
      <div className="titlebar-actions">
        <button className="toolbar-button" title="New session" onClick={onNewSsh}><Plus size={18}/><span>Session</span></button>
        <button className="toolbar-button" title="Remote files" onClick={() => openTab({ id: 'files', title: 'Remote Files', kind: 'files' })}><FolderOpen size={18}/><span>Files</span></button>
        <button className="toolbar-button" title="Toggle sidebar" onClick={() => useWorkspace.getState().toggleSidebar()}><Columns2 size={18}/><span>Panels</span></button>
        <button className="toolbar-button" title="Command palette" onClick={() => setPaletteOpen(true)}><Wrench size={18}/><span>Tools</span></button>
        <button className="toolbar-button" title="Quick connect" onClick={onQuickConnect}><Activity size={18}/><span>Connect</span></button>
        <button className="toolbar-button" title="Local terminal" onClick={onNewTerminal}><SquareTerminal size={18}/><span>Terminal</span></button>
        <button className="toolbar-button" title="Settings" onClick={onSettings}><Settings size={18}/><span>Settings</span></button>
        <button className="toolbar-button" title="Lock workspace" onClick={onLock}><LockKeyhole size={18}/><span>Lock</span></button>
        <button className="toolbar-button" title="About" onClick={onAbout}><Info size={18}/><span>About</span></button>
      </div>
      <button className="titlebar-search" onClick={() => setPaletteOpen(true)}>
        <Search size={14}/>
        <span>Search sessions…</span>
        <kbd>Ctrl+K</kbd>
      </button>
    </header>
  );
}
