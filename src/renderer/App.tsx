import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import type { SaveSession, Session } from '../../electron/contracts/sessions';
import type { Folder } from '../../electron/contracts/folders';
import type { AppSettings } from '../../electron/contracts/settings';
import { defaultSettings } from '../../electron/contracts/settings';
import TitleBar from './layouts/TitleBar';
import Sidebar from './layouts/Sidebar';
import TabBar from './layouts/TabBar';
import StatusBar from './layouts/StatusBar';
import CommandPalette from './components/CommandPalette';
import Toasts from './components/Toasts';
import HomePage from './features/home/HomePage';
import SessionsPage from './features/sessions/SessionsPage';
import SessionModal from './features/sessions/SessionModal';
import QuickConnectModal, { type QuickConnectValue } from './features/sessions/QuickConnectModal';
import ConnectionErrorModal from './features/sessions/ConnectionErrorModal';
import SettingsPage from './features/settings/SettingsPage';
import AboutPage from './features/about/AboutPage';
import TerminalView from './features/terminal/TerminalView';
import FilesPane from './features/files/FilesPane';
import { useWorkspace } from './stores/workspaceStore';
import Swal from 'sweetalert2';
import 'sweetalert2/dist/sweetalert2.min.css';

export default function App() {
  const tabs = useWorkspace(state => state.tabs);
  const activeTabId = useWorkspace(state => state.activeTabId);
  const openTab = useWorkspace(state => state.openTab);
  const closeTab = useWorkspace(state => state.closeTab);
  const updateTab = useWorkspace(state => state.updateTab);
  const toggleSidebar = useWorkspace(state => state.toggleSidebar);
  const setPaletteOpen = useWorkspace(state => state.setPaletteOpen);
  const pushToast = useWorkspace(state => state.pushToast);

  const [sessions, setSessions] = useState<Session[]>([]);
  const [favorites, setFavorites] = useState<Session[]>([]);
  const [folders, setFolders] = useState<Folder[]>([]);
  const [query, setQuery] = useState('');
  const [page, setPage] = useState(1);
  const [totalSessions, setTotalSessions] = useState(0);
  const [loading, setLoading] = useState(true);
  const [revision, setRevision] = useState(0);
  const [settings, setSettings] = useState<AppSettings>(defaultSettings);
  const [editing, setEditing] = useState<Session | null>(null);
  const [creating, setCreating] = useState<Session['kind'] | null>(null);
  const [quickConnect, setQuickConnect] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [aboutOpen, setAboutOpen] = useState(false);
  const [connectionError, setConnectionError] = useState<{ host: string; reason: string; session?: Session } | null>(null);
  const requestSequence = useRef(0);

  const closeWorkspaceTab = useCallback((id: string) => {
    const tab = useWorkspace.getState().tabs.find(item => item.id === id);
    if (tab?.kind === 'rdp' && tab.transportId) window.mori.rdp.disconnect(tab.transportId);
    closeTab(id);
  }, [closeTab]);

  const activeTab = tabs.find(tab => tab.id === activeTabId) ?? tabs[0];

  useEffect(() => {
    if (activeTab?.kind === 'settings') {
      setSettingsOpen(true);
      closeTab(activeTab.id);
    }
    if (activeTab?.kind === 'about') {
      setAboutOpen(true);
      closeTab(activeTab.id);
    }
  }, [activeTab, closeTab]);

  const refreshSessions = useCallback(async () => {
    const requestId = ++requestSequence.current;
    setLoading(true);
    try {
      const [list, favoriteList, folderList] = await Promise.all([
        window.mori.sessions.list({ query, page, pageSize: 10 }),
        window.mori.sessions.list({ favoritesOnly: true, page: 1, pageSize: 20 }),
        window.mori.folders.list(),
      ]);
      if (!list.ok) throw new Error(list.message);
      if (!favoriteList.ok) throw new Error(favoriteList.message);
      if (!folderList.ok) throw new Error(folderList.message);
      if (requestId !== requestSequence.current) return;
      setSessions(list.value.items);
      setTotalSessions(list.value.total);
      setFavorites(favoriteList.value.items);
      setFolders(folderList.value);
    } catch (error) {
      pushToast({
        title: 'Could not load sessions',
        message: error instanceof Error ? error.message : 'Please retry.',
        tone: 'error',
      });
    } finally {
      setLoading(false);
    }
  }, [page, query, pushToast]);

  useEffect(() => { void refreshSessions(); }, [refreshSessions, revision]);

  useEffect(() => {
    void window.mori.settings.get().then(setSettings).catch(() => undefined);
  }, []);

  useEffect(() => window.mori.ssh.onState(payload => {
    const tabId = `ssh-${payload.id}`;
    const status = payload.state === 'Connected' ? 'online'
      : payload.state === 'Connecting' || payload.state === 'Reconnecting' ? 'connecting'
        : payload.state.toLowerCase();
    updateTab(tabId, { status });
    if (payload.state === 'Disconnected') {
      pushToast({ title: 'SSH disconnected', message: 'The terminal tab is preserved. Reconnect when ready.', tone: 'info' });
    }
    if (payload.state === 'Failed' && payload.message) {
      pushToast({ title: 'SSH connection failed', message: payload.message, tone: 'error' });
    }
  }), [pushToast, updateTab]);

  const openLocalTerminal = useCallback(async () => {
    try {
      const started = await window.mori.pty.start({ cols: 120, rows: 32 });
      openTab({
        id: `pty-${started.id}`,
        title: started.shell.split(/[/\\]/).pop() || 'local',
        kind: 'terminal',
        transportId: started.id,
        status: 'online',
      });
    } catch (error) {
      pushToast({
        title: 'Terminal failed',
        message: error instanceof Error ? error.message : 'Could not start local shell',
        tone: 'error',
      });
    }
  }, [openTab, pushToast]);

  const connectSession = useCallback(async (session: Session, password?: string) => {
    if (session.kind === 'LOCAL') {
      await openLocalTerminal();
      return;
    }
    if (session.kind === 'RDP') {
      try {
        const status = await window.mori.rdp.status();
        if (!status.available) {
          setConnectionError({
            host: `${session.user}@${session.host}:${session.port ?? 3389}`,
            reason: status.hint,
            session,
          });
          return;
        }
        const id = crypto.randomUUID();
        const launched = await window.mori.rdp.connect({ id, sessionId: session.id });
        openTab({
          id: `rdp-${id}`,
          title: `RDP ${session.name}`,
          kind: 'rdp',
          sessionId: session.id,
          transportId: id,
          session,
          status: 'online',
        });
        pushToast({
          title: 'RDP launched',
          message: `${session.name} via ${launched.command.split(/[/\\]/).pop()}`,
          tone: 'success',
        });
      } catch (error) {
        setConnectionError({
          host: `${session.user}@${session.host}:${session.port ?? 3389}`,
          reason: ipcErrorMessage(error),
          session,
        });
      }
      return;
    }

    const id = crypto.randomUUID();
    openTab({
      id: `ssh-${id}`,
      title: `${session.user}@${session.host}`,
      kind: 'ssh',
      sessionId: session.id,
      transportId: id,
      session,
      status: 'connecting',
    });
    try {
      await window.mori.ssh.connect({ id, sessionId: session.id, password, cols: 120, rows: 32 });
      updateTab(`ssh-${id}`, { status: 'online' });
      pushToast({ title: 'SSH connected', message: `${session.user}@${session.host}` });
    } catch (error) {
      updateTab(`ssh-${id}`, { status: 'failed' });
      setConnectionError({
        host: `${session.user}@${session.host}:${session.port ?? 22}`,
        reason: friendlyError(error),
        session,
      });
    }
  }, [closeTab, closeWorkspaceTab, openLocalTerminal, openTab, pushToast, updateTab]);

  const persistSession = async (value: SaveSession) => {
    const result = await window.mori.sessions.save(value);
    if (!result.ok) throw new Error(result.message);
    setCreating(null);
    setEditing(null);
    setRevision(value => value + 1);
    pushToast({ title: 'Session saved', message: result.value.name, tone: 'success' });
  };

  const deleteSession = async (session: Session) => {
    const confirmation = await Swal.fire({
      title: 'Delete session?',
      text: `This will remove “${session.name}” and its saved credential.`,
      icon: 'warning',
      showCancelButton: true,
      confirmButtonText: 'Delete',
      cancelButtonText: 'Cancel',
      reverseButtons: true,
      focusCancel: true,
    });
    if (!confirmation.isConfirmed) return;
    const result = await window.mori.sessions.delete(session.id);
    if (!result.ok) {
      pushToast({ title: 'Delete failed', message: result.message, tone: 'error' });
      return;
    }
    setRevision(value => value + 1);
    pushToast({ title: 'Session deleted', message: session.name });
  };

  const duplicateSession = async (session: Session) => {
    const result = await window.mori.sessions.duplicate(session.id);
    if (!result.ok) {
      pushToast({ title: 'Duplicate failed', message: result.message, tone: 'error' });
      return;
    }
    setRevision(value => value + 1);
    pushToast({ title: 'Session duplicated', message: result.value.name, tone: 'success' });
  };

  const moveSession = async (session: Session, group: string) => {
    const { hasPassword: _hasPassword, ...editable } = session;
    const result = await window.mori.sessions.save({ ...editable, group });
    if (!result.ok) {
      pushToast({ title: 'Move failed', message: result.message, tone: 'error' });
      return;
    }
    setRevision(value => value + 1);
    pushToast({ title: 'Session moved', message: `${session.name} → ${group}`, tone: 'success' });
  };

  const createFolder = async () => {
    const prompt = await Swal.fire({
      title: 'New folder',
      input: 'text',
      inputLabel: 'Folder path',
      inputPlaceholder: 'Production/Web Servers',
      showCancelButton: true,
      confirmButtonText: 'Create',
      cancelButtonText: 'Cancel',
      reverseButtons: true,
      inputValidator: value => !value.trim() ? 'Enter a folder path.' : undefined,
    });
    if (!prompt.isConfirmed || typeof prompt.value !== 'string') return;
    const result = await window.mori.folders.create(prompt.value);
    if (!result.ok) { pushToast({ title: 'Folder creation failed', message: result.message, tone: 'error' }); return; }
    setRevision(value => value + 1);
    pushToast({ title: 'Folder created', message: result.value.path, tone: 'success' });
  };

  const renameFolder = async (folder: Folder) => {
    const currentName = folder.path.split('/').pop() ?? folder.path;
    const prompt = await Swal.fire({
      title: 'Rename folder',
      input: 'text',
      inputValue: currentName,
      inputLabel: 'Folder name',
      showCancelButton: true,
      confirmButtonText: 'Rename',
      cancelButtonText: 'Cancel',
      reverseButtons: true,
      inputValidator: value => !value.trim() || value.includes('/') ? 'Enter one folder name without /. ' : undefined,
    });
    if (!prompt.isConfirmed || typeof prompt.value !== 'string') return;
    const result = await window.mori.folders.rename(folder.path, prompt.value);
    if (!result.ok) { pushToast({ title: 'Folder rename failed', message: result.message, tone: 'error' }); return; }
    setRevision(value => value + 1);
    pushToast({ title: 'Folder renamed', message: result.value.path, tone: 'success' });
  };

  const deleteFolder = async (folder: Folder) => {
    const confirmation = await Swal.fire({
      title: 'Delete folder?',
      text: `Sessions inside “${folder.path}” will be kept but ungrouped.`,
      icon: 'warning',
      showCancelButton: true,
      confirmButtonText: 'Delete',
      cancelButtonText: 'Cancel',
      reverseButtons: true,
      focusCancel: true,
    });
    if (!confirmation.isConfirmed) return;
    const result = await window.mori.folders.delete(folder.path);
    if (!result.ok) { pushToast({ title: 'Folder deletion failed', message: result.message, tone: 'error' }); return; }
    setRevision(value => value + 1);
    pushToast({ title: 'Folder deleted', message: folder.path, tone: 'success' });
  };

  const handleQuickConnect = async (value: QuickConnectValue) => {
    let session: Session;
    if (value.save) {
      const saved = await window.mori.sessions.save({
        name: value.name || `${value.username}@${value.host}`,
        host: value.host,
        port: value.port,
        user: value.username,
        kind: 'SSH',
        color: '#38d9c3',
        group: '',
        favorite: false,
        password: value.password,
      });
      if (!saved.ok) throw new Error(saved.message);
      session = saved.value;
      setRevision(value => value + 1);
    } else {
      const saved = await window.mori.sessions.save({
        name: `tmp-${Date.now()}`,
        host: value.host,
        port: value.port,
        user: value.username,
        kind: 'SSH',
        color: '#38d9c3',
        group: 'Quick',
        favorite: false,
        password: value.password,
      });
      if (!saved.ok) throw new Error(saved.message);
      session = saved.value;
      setRevision(value => value + 1);
    }
    setQuickConnect(false);
    await connectSession(session, value.password);
  };

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.ctrlKey && event.shiftKey && event.key.toLowerCase() === 'p') {
        event.preventDefault();
        setPaletteOpen(true);
      }
      if (event.ctrlKey && event.key.toLowerCase() === 'k' && !event.shiftKey) {
        event.preventDefault();
        setPaletteOpen(true);
      }
      if (event.ctrlKey && event.shiftKey && event.key.toLowerCase() === 't') {
        event.preventDefault();
        void openLocalTerminal();
      }
      if (event.ctrlKey && event.shiftKey && event.key.toLowerCase() === 'w') {
        event.preventDefault();
        if (activeTabId !== 'home') closeWorkspaceTab(activeTabId);
      }
      if (event.ctrlKey && event.key.toLowerCase() === 'b') {
        event.preventDefault();
        toggleSidebar();
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [activeTabId, closeWorkspaceTab, openLocalTerminal, setPaletteOpen, toggleSidebar]);

  useEffect(() => window.mori.onMenuCommand(command => {
    if (command === 'new-terminal') void openLocalTerminal();
    if (command === 'new-ssh') setCreating('SSH');
    if (command === 'new-rdp') setCreating('RDP');
    if (command === 'toggle-sidebar') toggleSidebar();
    if (command === 'about') setAboutOpen(true);
  }), [openLocalTerminal, toggleSidebar]);

  const commands = useMemo(() => [
    { id: 'new-terminal', label: 'New Terminal', run: () => void openLocalTerminal() },
    { id: 'new-ssh', label: 'New SSH Session', run: () => setCreating('SSH') },
    { id: 'new-rdp', label: 'New RDP Session', run: () => setCreating('RDP') },
    { id: 'quick-connect', label: 'Quick SSH Connect', run: () => setQuickConnect(true) },
    { id: 'sessions', label: 'Open Sessions', run: () => openTab({ id: 'sessions', title: 'Sessions', kind: 'sessions' }) },
    { id: 'settings', label: 'Open Settings', run: () => setSettingsOpen(true) },
    { id: 'toggle-sidebar', label: 'Toggle Sidebar', run: () => toggleSidebar() },
    { id: 'about', label: 'About MoriXterm', run: () => setAboutOpen(true) },
  ], [openLocalTerminal, openTab, toggleSidebar]);

  return (
    <div className="app-shell">
      <TitleBar
        onQuickConnect={() => setQuickConnect(true)}
        onNewTerminal={() => void openLocalTerminal()}
        onNewSsh={() => setCreating('SSH')}
        onSettings={() => setSettingsOpen(true)}
        onAbout={() => setAboutOpen(true)}
      />
      <div className="workspace-body">
        <Sidebar
          sessions={sessions}
          folders={folders}
          onConnect={session => void connectSession(session)}
          onMove={(session, group) => void moveSession(session, group)}
          onCreateFolder={() => void createFolder()}
          onRenameFolder={folder => void renameFolder(folder)}
          onDeleteFolder={folder => void deleteFolder(folder)}
          onNewTerminal={() => void openLocalTerminal()}
          onNewSession={() => setCreating('SSH')}
          onEditSession={setEditing}
          onDeleteSession={session => void deleteSession(session)}
        />
        <main className="workspace-main">
          <TabBar onCloseTab={closeWorkspaceTab}/>
          <div className="workspace-content">
            {activeTab?.kind === 'home' && (
              <HomePage
                sessions={sessions}
                favorites={favorites}
                onNewTerminal={() => void openLocalTerminal()}
                onNewSsh={() => setCreating('SSH')}
                onNewRdp={() => setCreating('RDP')}
                onConnect={session => void connectSession(session)}
                onOpenSessions={() => openTab({ id: 'sessions', title: 'Sessions', kind: 'sessions' })}
              />
            )}
            {activeTab?.kind === 'sessions' && (
              <SessionsPage
                sessions={sessions}
                query={query}
                total={totalSessions}
                page={page}
                pageSize={10}
                onQuery={value => { setQuery(value); setPage(1); }}
                onPage={setPage}
                onConnect={session => void connectSession(session)}
                onEdit={setEditing}
                onDuplicate={session => void duplicateSession(session)}
                onDelete={session => void deleteSession(session)}
                onNew={() => setCreating('SSH')}
                loading={loading}
              />
            )}
            {activeTab?.kind === 'files' && <Placeholder title="Remote files" text="SFTP/SCP file manager arrives in Phase 3."/>}
            {activeTab?.kind === 'snippets' && <Placeholder title="Snippets" text="Command snippets arrive in Phase 5."/>}
            {activeTab?.kind === 'terminal' && !activeTab.transportId && (
              <Placeholder title="Terminal" text="Open a local shell from Home or press Ctrl+Shift+T." actionLabel="New terminal" onAction={() => void openLocalTerminal()}/>
            )}
            {activeTab?.kind === 'rdp' && activeTab.session && (
              <div className="page">
                <p className="eyebrow">RDP SESSION</p>
                <h1>{activeTab.session.name}</h1>
                <p className="hero-copy">
                  Desktop session for <strong>{activeTab.session.user}@{activeTab.session.host}:{activeTab.session.port ?? 3389}</strong> was launched in the FreeRDP / system RDP client.
                </p>
                <p className="empty-state">Close this tab to disconnect the RDP process from MoriXterm.</p>
              </div>
            )}
            {tabs.filter(tab => (tab.kind === 'terminal' || tab.kind === 'ssh') && tab.transportId).map(tab => (
              <div key={tab.id} className={`terminal-pane ${tab.id === activeTabId ? 'active' : ''}`}>
                {tab.kind === 'ssh' ? (
                  <div className="remote-workspace">
                    <div className="remote-terminal"><TerminalView transport="ssh" transportId={tab.transportId!} settings={settings} session={tab.session}/></div>
                    {tab.status === 'online' && <FilesPane transportId={tab.transportId!} onError={message => pushToast({ title: 'Remote files failed', message, tone: 'error' })} onNotice={message => pushToast({ title: 'Remote files', message, tone: 'success' })}/>}
                  </div>
                ) : <TerminalView transport="pty" transportId={tab.transportId!} settings={settings} session={tab.session}/>}
              </div>
            ))}
          </div>
          <StatusBar target={activeTab?.transportId && (activeTab.kind === 'ssh' || activeTab.kind === 'terminal') ? { transport: activeTab.kind === 'ssh' ? 'ssh' : 'pty', id: activeTab.transportId } : undefined}/>
        </main>
      </div>
      <CommandPalette commands={commands}/>
      <Toasts/>
      {creating && <SessionModal initialKind={creating} onCancel={() => setCreating(null)} onSave={persistSession}/>}
      {editing && <SessionModal initial={editing} onCancel={() => setEditing(null)} onSave={persistSession}/>}
      {quickConnect && <QuickConnectModal onCancel={() => setQuickConnect(false)} onConnect={handleQuickConnect}/>}
      {settingsOpen && <ModalShell eyebrow="SETTINGS" title="Preferences" onClose={() => setSettingsOpen(false)}><SettingsPage compact settings={settings} onSave={async value => { const saved = await window.mori.settings.set(value); setSettings(saved); }}/></ModalShell>}
      {aboutOpen && <ModalShell eyebrow="ABOUT" title="MoriXterm" onClose={() => setAboutOpen(false)}><AboutPage compact/></ModalShell>}
      {connectionError && (
        <ConnectionErrorModal
          host={connectionError.host}
          reason={connectionError.reason}
          onClose={() => setConnectionError(null)}
          onRetry={connectionError.session ? () => {
            const session = connectionError.session!;
            setConnectionError(null);
            void connectSession(session);
          } : undefined}
          onEdit={connectionError.session ? () => {
            setEditing(connectionError.session!);
            setConnectionError(null);
          } : undefined}
        />
      )}
    </div>
  );
}

function ModalShell({ eyebrow, title, onClose, children }: { eyebrow: string; title: string; onClose: () => void; children: ReactNode }) {
  const dialog = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    dialog.current?.showModal();
    return () => { if (dialog.current?.open) dialog.current.close(); };
  }, []);
  return <dialog ref={dialog} className="session-dialog utility-dialog" onCancel={event => { event.preventDefault(); onClose(); }}>
    <div className="session-modal utility-modal">
      <div className="modal-head"><div><p className="eyebrow">{eyebrow}</p><h2>{title}</h2></div><button className="icon-button" type="button" aria-label={`Close ${title}`} onClick={onClose}>×</button></div>
      {children}
    </div>
  </dialog>;
}

function Placeholder({ title, text, actionLabel, onAction }: { title: string; text: string; actionLabel?: string; onAction?: () => void }) {
  return (
    <div className="page">
      <p className="eyebrow">WORKSPACE</p>
      <h1>{title}</h1>
      <p className="hero-copy">{text}</p>
      {actionLabel && onAction && <button className="new-button" onClick={onAction}>{actionLabel}</button>}
    </div>
  );
}

function friendlyError(error: unknown): string {
  const message = ipcErrorMessage(error);
  if (/timed out|Timeout/i.test(message)) return 'Connection timed out';
  if (/ECONNREFUSED|refused/i.test(message)) return 'Connection refused';
  if (/Authentication|All configured authentication methods failed/i.test(message)) return 'Authentication failed';
  if (/ENOTFOUND|getaddrinfo/i.test(message)) return 'Host could not be resolved';
  return message || 'Connection failed';
}

function ipcErrorMessage(error: unknown): string {
  const raw = error instanceof Error ? error.message : String(error);
  const nested = raw.match(/Error invoking remote method '[^']+': (?:Error: )?(.+)$/s);
  return (nested?.[1] ?? raw).trim();
}
