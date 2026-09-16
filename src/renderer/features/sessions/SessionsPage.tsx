import { ChevronLeft, ChevronRight, Copy, Laptop, Monitor, Pencil, Plus, Search, Server, Star, Trash2 } from 'lucide-react';
import type { Session } from '../../../../electron/contracts/sessions';
import PlatformIcon from '../../components/PlatformIcon';

export default function SessionsPage({
  sessions,
  query,
  total,
  page,
  pageSize,
  onQuery,
  onPage,
  onConnect,
  onEdit,
  onDelete,
  onDuplicate,
  onNew,
  loading,
}: {
  sessions: Session[];
  query: string;
  total: number;
  page: number;
  pageSize: number;
  onQuery: (value: string) => void;
  onPage: (page: number) => void;
  onConnect: (session: Session) => void;
  onEdit: (session: Session) => void;
  onDelete: (session: Session) => void;
  onDuplicate: (session: Session) => void;
  onNew: () => void;
  loading: boolean;
}) {
  return (
    <div className="page">
      <div className="page-toolbar">
        <div>
          <p className="eyebrow">SESSIONS</p>
          <h1>Connection manager</h1>
        </div>
        <button className="new-button" onClick={onNew}><Plus size={15}/> New session</button>
      </div>
      <div className="panel">
        <div className="panel-toolbar">
          <div className="search">
            <Search size={15}/>
            <input value={query} onChange={event => onQuery(event.target.value)} placeholder="Search sessions…"/>
          </div>
        </div>
        {loading && <p className="empty-state">Loading sessions…</p>}
        {!loading && sessions.length === 0 && <p className="empty-state">No matching sessions.</p>}
        {sessions.map(session => (
          <div key={session.id} className="session-row">
            <button className="session-connect" onClick={() => onConnect(session)}>
              <span className="session-type" style={{ color: session.color }}>
                <PlatformIcon platform={session.platform} size={16}/>
              </span>
              <span className="session-main">
                <strong>{session.name}{session.favorite ? <Star size={12} className="fav-inline"/> : null}</strong>
                <small>{session.user}@{session.host}{session.port ? `:${session.port}` : ''} · {session.kind}</small>
              </span>
              {session.group && <span className="tag">{session.group}</span>}
            </button>
            <button className="row-edit" title="Edit" onClick={() => onEdit(session)}><Pencil size={14}/></button>
            <button className="row-edit" title="Duplicate" onClick={() => onDuplicate(session)}><Copy size={14}/></button>
            <button className="row-edit danger" title="Delete" onClick={() => onDelete(session)}><Trash2 size={14}/></button>
          </div>
        ))}
        {total > 0 && (
          <div className="pagination" aria-label="Session pagination">
            <span>Showing {(page - 1) * pageSize + 1}–{Math.min(page * pageSize, total)} of {total}</span>
            <span className="pagination-actions">
              <button aria-label="Previous page" disabled={page <= 1} onClick={() => onPage(page - 1)}><ChevronLeft size={14}/></button>
              <span>Page {page} of {Math.max(1, Math.ceil(total / pageSize))}</span>
              <button aria-label="Next page" disabled={page >= Math.ceil(total / pageSize)} onClick={() => onPage(page + 1)}><ChevronRight size={14}/></button>
            </span>
          </div>
        )}
      </div>
    </div>
  );
}
