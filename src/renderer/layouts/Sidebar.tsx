import { ChevronDown, ChevronRight, Folder, FolderPlus, Inbox, Pencil, Plus, Trash2 } from 'lucide-react';
import type { Session } from '../../../electron/contracts/sessions';
import type { Folder as FolderModel } from '../../../electron/contracts/folders';
import type { DragEvent } from 'react';
import { useMemo, useState } from 'react';
import { useWorkspace } from '../stores/workspaceStore';
import PlatformIcon from '../components/PlatformIcon';

export default function Sidebar({
  sessions, folders, onConnect, onMove, onCreateFolder, onRenameFolder, onDeleteFolder, onNewSession, onEditSession, onDeleteSession,
}: {
  sessions: Session[];
  folders: FolderModel[];
  onConnect: (session: Session) => void;
  onMove: (session: Session, group: string) => void;
  onCreateFolder: () => void;
  onRenameFolder: (folder: FolderModel) => void;
  onDeleteFolder: (folder: FolderModel) => void;
  onNewTerminal: () => void;
  onNewSession: () => void;
  onEditSession: (session: Session) => void;
  onDeleteSession: (session: Session) => void;
}) {
  const collapsed = useWorkspace(state => state.sidebarCollapsed);
  const [context, setContext] = useState<{ session: Session; x: number; y: number } | null>(null);
  const [collapsedGroups, setCollapsedGroups] = useState<Set<string>>(new Set());
  const groups = useMemo(() => {
    const known = folders.map(folder => folder.path);
    sessions.forEach(session => { if (session.group && !known.includes(session.group)) known.push(session.group); });
    return ['', ...known.sort((a, b) => a.localeCompare(b))];
  }, [folders, sessions]);

  const toggleGroup = (group: string) => setCollapsedGroups(current => {
    const next = new Set(current);
    if (next.has(group)) next.delete(group); else next.add(group);
    return next;
  });
  const dropSession = (event: DragEvent<HTMLDivElement>, group: string) => {
    event.preventDefault();
    const session = sessions.find(item => item.id === event.dataTransfer.getData('application/x-morixterm-session'));
    if (session && session.group !== group) onMove(session, group);
  };

  return (
    <aside className={`sidebar ${collapsed ? 'collapsed' : ''}`} onClick={() => context && setContext(null)}>
      <div className="sidebar-head">
        {!collapsed && <><span>User sessions</span><button title="New folder" aria-label="New folder" onClick={onCreateFolder}><FolderPlus size={16}/></button></>}
      </div>
      {!collapsed && <div className="session-list-only">
        {groups.map(group => {
          const folder = folders.find(item => item.path === group);
          const groupSessions = sessions.filter(session => (session.group || '') === group);
          const isCollapsed = collapsedGroups.has(group);
          return <div className="session-group" key={group} onDragOver={event => event.preventDefault()} onDrop={event => dropSession(event, group)}>
            <div className="session-group-title">
              <button className="group-toggle" onClick={() => toggleGroup(group)} aria-label={`${isCollapsed ? 'Expand' : 'Collapse'} ${group || 'No folder'}`}>
                {isCollapsed ? <ChevronRight size={16}/> : <ChevronDown size={16}/>} {group ? <Folder size={15}/> : <Inbox size={15}/>} <span>{group || 'No folder'}</span>
              </button>
              <button title="New session" aria-label="New session" onClick={onNewSession}><Plus size={15}/></button>
              {folder && <><button title="Rename folder" aria-label="Rename folder" onClick={() => onRenameFolder(folder)}><Pencil size={14}/></button><button className="danger" title="Delete folder" aria-label="Delete folder" onClick={() => onDeleteFolder(folder)}><Trash2 size={15}/></button></>}
            </div>
            {!isCollapsed && groupSessions.map(session => <button key={session.id} className="favorite-row" draggable onDragStart={event => { event.dataTransfer.effectAllowed = 'move'; event.dataTransfer.setData('application/x-morixterm-session', session.id); }} onClick={() => onConnect(session)} onContextMenu={event => { event.preventDefault(); event.stopPropagation(); setContext({ session, x: event.clientX, y: event.clientY }); }}>
              <span className="session-platform" style={{ color: session.color }}><PlatformIcon platform={session.platform} size={16}/></span><span><strong>{session.name}</strong><small>{session.kind} {session.host}</small></span>
            </button>)}
          </div>;
        })}
      </div>}
      {!collapsed && <div className="sidebar-status"><i className="status-dot"/><span>Session workspace</span></div>}
      {context && <div className="session-context-menu" style={{ left: context.x, top: context.y }} onClick={event => event.stopPropagation()}>
        <button onClick={() => { onEditSession(context.session); setContext(null); }}><Pencil size={13}/> Edit session</button>
        <button className="danger" onClick={() => { onDeleteSession(context.session); setContext(null); }}><Trash2 size={13}/> Delete session</button>
      </div>}
    </aside>
  );
}
