import { ArrowDown, ArrowUp, ChevronLeft, ChevronRight, Clipboard, Copy, Download, File, Folder, FolderOpen, FolderPlus, Home, Link2, LockKeyhole, Pencil, RefreshCw, Search, Scissors, Shield, Trash2, Upload, UserRound, X } from 'lucide-react';
import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent, type PointerEvent as ReactPointerEvent } from 'react';
import type { RemoteFile } from '../../../../electron/contracts/files';
import Swal from 'sweetalert2';

type AccessModal = 'permissions' | 'owner';

export default function FilesPane({ transportId, onError, onNotice }: { transportId: string; onError: (message: string) => void; onNotice: (message: string) => void }) {
  // Start in the SSH user's home directory. `/` is commonly readable but not writable.
  const [path, setPath] = useState('.');
  const [entries, setEntries] = useState<RemoteFile[]>([]);
  const [loading, setLoading] = useState(true);
  const [selected, setSelected] = useState<RemoteFile | null>(null);
  const [clipboard, setClipboard] = useState<{ path: string; cut: boolean } | null>(null);
  const [accessModal, setAccessModal] = useState<AccessModal | null>(null);
  const [fileMenu, setFileMenu] = useState<{ file: RemoteFile; x: number; y: number } | null>(null);
  const [transfer, setTransfer] = useState<{ direction: 'upload' | 'download'; transferred: number; total: number } | null>(null);
  const [width, setWidth] = useState(320);
  const [query, setQuery] = useState('');
  const [page, setPage] = useState(1);
  const pageSize = 50;
  const loadSequence = useRef(0);
  function startResize(event: ReactPointerEvent<HTMLDivElement>) {
    event.currentTarget.setPointerCapture(event.pointerId);
    const startX = event.clientX;
    const startWidth = width;
    const move = (moveEvent: PointerEvent) => setWidth(Math.max(190, Math.min(520, startWidth - (moveEvent.clientX - startX))));
    const stop = () => { window.removeEventListener('pointermove', move); window.removeEventListener('pointerup', stop); };
    window.addEventListener('pointermove', move);
    window.addEventListener('pointerup', stop, { once: true });
  }

  useEffect(() => window.mori.files.onProgress(value => {
    if (value.id !== transportId) return;
    if (value.complete) { setTransfer(null); return; }
    setTransfer({ direction: value.direction, transferred: value.transferred, total: value.total });
  }), [transportId]);

  const load = useCallback(async (nextPath = path) => {
    const requestId = ++loadSequence.current;
    setLoading(true);
    try {
      const result = await window.mori.files.list({ id: transportId, path: nextPath });
      if (requestId !== loadSequence.current) return;
      if (!result.ok) onError(result.message);
      else { setPath(nextPath); setEntries(result.value); setSelected(null); setPage(1); }
    } catch {
      if (requestId === loadSequence.current) onError('Could not reach the SFTP service.');
    } finally {
      if (requestId === loadSequence.current) setLoading(false);
    }
  }, [onError, path, transportId]);

  useEffect(() => { void load('.'); }, [transportId]);

  const breadcrumbs = useMemo(() => {
    const parts = path.split('/').filter(Boolean);
    const visible = parts.filter(part => part !== '.');
    return visible.map((part, index) => ({ label: part, path: `./${visible.slice(0, index + 1).join('/')}` }));
  }, [path]);

  const filteredEntries = useMemo(() => {
    const needle = query.trim().toLocaleLowerCase();
    return [...entries]
      .filter(entry => !needle || entry.name.toLocaleLowerCase().includes(needle))
      .sort((left, right) => Number(right.type === 'directory') - Number(left.type === 'directory') || left.name.localeCompare(right.name));
  }, [entries, query]);
  const pageCount = Math.max(1, Math.ceil(filteredEntries.length / pageSize));
  const visibleEntries = filteredEntries.slice((page - 1) * pageSize, page * pageSize);

  function parentPath() {
    if (path === '.' || path === '/') return;
    const parts = path.split('/').filter(Boolean);
    parts.pop();
    void load(parts.length ? `/${parts.join('/')}` : '.');
  }

  const refresh = () => void load();
  const selectedPath = selected?.path;
  async function action(result: Promise<{ ok: boolean; message?: string }>, success: string): Promise<boolean> {
    try {
      const response = await result;
      if (!response.ok) { onError(response.message ?? 'Remote file operation failed.'); return false; }
      setSelected(null); await load();
      onNotice(success);
      return true;
    } catch { onError('Remote file operation failed.'); return false; }
  }

  async function makeDirectory() {
    const prompt = await Swal.fire({ title: 'New directory', input: 'text', inputLabel: 'Directory name', showCancelButton: true, confirmButtonText: 'Create', cancelButtonText: 'Cancel', reverseButtons: true, inputValidator: value => value.trim() ? undefined : 'Enter a directory name.' });
    if (prompt.isConfirmed && typeof prompt.value === 'string') await action(window.mori.files.mkdir({ id: transportId, path: joinPath(path, prompt.value) }), 'Directory created.');
  }
  async function renameSelected(file = selected) {
    if (!file) return;
    const prompt = await Swal.fire({ title: 'Rename remote item', input: 'text', inputValue: file.name, showCancelButton: true, confirmButtonText: 'Rename', cancelButtonText: 'Cancel', reverseButtons: true, inputValidator: value => value.trim() ? undefined : 'Enter a name.' });
    if (prompt.isConfirmed && typeof prompt.value === 'string') await action(window.mori.files.rename({ id: transportId, path: file.path, newPath: joinPath(path, prompt.value) }), 'Item renamed.');
  }
  async function deleteSelected(file = selected) {
    if (!file) return;
    const confirmation = await Swal.fire({ title: 'Delete remote item?', text: file.name, icon: 'warning', showCancelButton: true, confirmButtonText: 'Delete', cancelButtonText: 'Cancel', reverseButtons: true });
    if (confirmation.isConfirmed) await action(window.mori.files.delete({ id: transportId, path: file.path, directory: file.type === 'directory' }), 'Item deleted.');
  }
  async function paste() {
    if (!clipboard) return;
    const target = joinPath(path, clipboard.path.split('/').pop() ?? 'copy');
    await action(window.mori.files.copy({ id: transportId, source: clipboard.path, target }), 'Item pasted.');
    if (clipboard.cut) await action(window.mori.files.delete({ id: transportId, path: clipboard.path }), 'Item moved.');
    setClipboard(null);
  }

  return (
    <aside className="files-pane" style={{ width }} aria-label="Remote files" onClick={() => fileMenu && setFileMenu(null)}>
      <div className="panel-resizer panel-resizer-left" onPointerDown={startResize} role="separator" aria-label="Resize remote files panel"/>
      <div className="files-head">
        <div className="files-title"><span className="files-title-icon"><FolderOpen size={17}/></span><span><strong>Remote files</strong><small>SFTP workspace</small></span></div>
        <div className="files-head-meta"><span className="files-connection" title="SFTP connected"><Link2 size={14}/></span><button className="icon-button files-close" title="Clear file selection" aria-label="Clear file selection" onClick={() => { setSelected(null); setQuery(''); }}><X size={15}/></button></div>
      </div>
      <div className="files-toolbar">
        <button className="icon-button" title="Parent directory" aria-label="Parent directory" disabled={path === '.' || path === '/' || loading} onClick={parentPath}><ChevronLeft size={14}/></button>
        <button className="icon-button" title="Refresh" aria-label="Refresh files" disabled={loading} onClick={() => void load()}><RefreshCw className={loading ? 'spin' : ''} size={14}/></button>
        <button className="icon-button" title="Upload file" aria-label="Upload file" disabled={loading} onClick={() => void action(window.mori.files.upload({ id: transportId, remotePath: path }), 'File uploaded.')}><ArrowUp size={14}/></button>
        <button className="icon-button" title="Download selected" aria-label="Download selected" disabled={!selected || selected.type === 'directory'} onClick={() => selected && void action(window.mori.files.download({ id: transportId, remotePath: selected.path }), 'File downloaded.')}><ArrowDown size={14}/></button>
        <button className="icon-button" title="New folder" aria-label="New folder" disabled={loading} onClick={() => void makeDirectory()}><FolderPlus size={14}/></button>
        <button className="icon-button" title="Copy selected" aria-label="Copy selected" disabled={!selected} onClick={() => selected && setClipboard({ path: selected.path, cut: false })}><Copy size={14}/></button>
        <button className="icon-button" title="Cut selected" aria-label="Cut selected" disabled={!selected} onClick={() => selected && setClipboard({ path: selected.path, cut: true })}><Scissors size={14}/></button>
        <button className="icon-button" title="Paste" aria-label="Paste" disabled={!clipboard} onClick={() => void paste()}><Clipboard size={14}/></button>
        <button className="icon-button" title="Rename selected" aria-label="Rename selected" disabled={!selected} onClick={() => void renameSelected()}><Pencil size={14}/></button>
        <button className="icon-button" title="Permissions" aria-label="Permissions" disabled={!selected} onClick={() => setAccessModal('permissions')}><LockKeyhole size={14}/></button>
        <code title={path}>{path}</code>
      </div>
      <div className="files-breadcrumbs">
        <button className="files-home" onClick={() => void load('.')} aria-label="Home directory"><Home size={13}/></button>
        {breadcrumbs.map(item => <span key={item.path}><ChevronRight size={11}/><button onClick={() => void load(item.path)}>{item.label}</button></span>)}
      </div>
      <div className="files-primary-actions" aria-label="Primary file actions">
        <button className="files-primary" onClick={() => void action(window.mori.files.upload({ id: transportId, remotePath: path }), 'File uploaded.')}><Upload size={14}/><span>Upload</span></button>
        <button className="files-secondary" onClick={() => void makeDirectory()}><FolderPlus size={14}/><span>New folder</span></button>
      </div>
      <div className="files-search">
        <Search size={13}/><input value={query} onChange={event => { setQuery(event.target.value); setPage(1); }} placeholder="Filter this folder…" aria-label="Filter files"/>
        {query && <button aria-label="Clear file filter" onClick={() => { setQuery(''); setPage(1); }}><X size={12}/></button>}
      </div>
      {selected && <div className="files-selection" aria-label="Selected file actions">
        <span className="files-selection-name" title={selected.name}>{selected.name}</span>
        <button title="Download selected" aria-label="Download selected" disabled={selected.type === 'directory'} onClick={() => void action(window.mori.files.download({ id: transportId, remotePath: selectedPath! }), 'File downloaded.')}><Download size={13}/></button>
        <button title="Copy" aria-label="Copy selected" disabled={!selected} onClick={() => selected && setClipboard({ path: selected.path, cut: false })}><Copy size={13}/></button>
        <button title="Cut" aria-label="Cut selected" disabled={!selected} onClick={() => selected && setClipboard({ path: selected.path, cut: true })}><Scissors size={13}/></button>
        <button title="Rename" aria-label="Rename selected" disabled={!selected} onClick={() => void renameSelected()}><Pencil size={13}/></button>
        <button title="Permissions" aria-label="Change permissions" disabled={!selected} onClick={() => setAccessModal('permissions')}><Shield size={13}/></button>
        <button title="Owner" aria-label="Change owner" disabled={!selected} onClick={() => setAccessModal('owner')}><UserRound size={13}/></button>
        <button title="Delete" aria-label="Delete selected" disabled={!selected} onClick={() => void deleteSelected()}><Trash2 size={13}/></button>
        <button className="files-selection-close" title="Clear selection" aria-label="Clear selection" onClick={() => setSelected(null)}><X size={13}/></button>
      </div>}
      {clipboard && <div className="files-clipboard" role="status"><Clipboard size={13}/><span title={clipboard.path}>{clipboard.cut ? 'Move' : 'Copy'}: {clipboard.path.split('/').pop()}</span><button onClick={() => void paste()}>Paste here</button><button className="files-clipboard-clear" aria-label="Clear clipboard" onClick={() => setClipboard(null)}><X size={12}/></button></div>}
      {transfer && <div className="file-transfer" role="status">
        <div className="file-transfer-head"><strong>{transfer.direction === 'upload' ? 'Uploading file' : 'Downloading file'}</strong><span>{Math.round(Math.min(1, transfer.transferred / Math.max(1, transfer.total)) * 100)}%</span></div>
        <div className="file-transfer-track"><span style={{ width: `${Math.min(100, transfer.transferred / Math.max(1, transfer.total) * 100)}%` }}/></div>
        <small>{formatBytes(transfer.transferred)} / {formatBytes(transfer.total)}</small>
      </div>}
      {fileMenu && <div className="file-context-menu" style={{ left: fileMenu.x, top: fileMenu.y }} onClick={event => event.stopPropagation()}>
        <div className="file-context-title"><strong>{fileMenu.file.name}</strong><small>{fileMenu.file.type === 'directory' ? 'Directory' : formatBytes(fileMenu.file.size)}</small></div>
        <button disabled={fileMenu.file.type === 'directory'} onClick={() => { setSelected(fileMenu.file); void action(window.mori.files.download({ id: transportId, remotePath: fileMenu.file.path }), 'File downloaded.'); setFileMenu(null); }}><Download size={13}/>Download</button>
        <button onClick={() => { setClipboard({ path: fileMenu.file.path, cut: false }); setFileMenu(null); }}><Copy size={13}/>Copy</button>
        <button onClick={() => { setClipboard({ path: fileMenu.file.path, cut: true }); setFileMenu(null); }}><Scissors size={13}/>Cut</button>
        <button disabled={!clipboard} onClick={() => { setFileMenu(null); void paste(); }}><Clipboard size={13}/>Paste here</button>
        <span className="file-context-separator"/>
        <button onClick={() => { setSelected(fileMenu.file); setFileMenu(null); void renameSelected(fileMenu.file); }}><Pencil size={13}/>Rename</button>
        <button onClick={() => { setSelected(fileMenu.file); setAccessModal('permissions'); setFileMenu(null); }}><Shield size={13}/>Permissions</button>
        <button onClick={() => { setSelected(fileMenu.file); setAccessModal('owner'); setFileMenu(null); }}><UserRound size={13}/>Owner</button>
        <span className="file-context-separator"/>
        <button className="danger" onClick={() => { const file = fileMenu.file; setFileMenu(null); void deleteSelected(file); }}><Trash2 size={13}/>Delete</button>
      </div>}
      {selected && accessModal && <FileAccessModal
        kind={accessModal}
        file={selected}
        onCancel={() => setAccessModal(null)}
        onApply={async (kind, value) => {
          const success = kind === 'permissions'
            ? await action(window.mori.files.chmod({ id: transportId, path: selected.path, mode: value.mode }), 'Permissions updated.')
            : await action(window.mori.files.chown({ id: transportId, path: selected.path, uid: value.uid, gid: value.gid }), 'Owner updated.');
          if (success) setAccessModal(null);
        }}
      />}
      <div className="files-list">
        {!loading && filteredEntries.length > 0 && <div className="files-list-head"><span>Name</span><span>Access</span></div>}
        {loading && <div className="files-loading" aria-label="Loading files">{Array.from({ length: 6 }, (_, index) => <span key={index}/>)}</div>}
        {!loading && filteredEntries.length === 0 && <div className="files-empty"><FolderOpen size={28}/><strong>{query ? 'No matching files' : 'This folder is empty'}</strong><small>{query ? 'Try a different search term.' : 'Upload a file or create a new folder.'}</small></div>}
        {!loading && visibleEntries.map(entry => (
          <button key={entry.path} className={`file-row ${selected?.path === entry.path ? 'selected' : ''}`} onClick={() => setSelected(entry)} onContextMenu={event => { event.preventDefault(); const rect = (event.currentTarget.closest('.files-pane') as HTMLElement).getBoundingClientRect(); setFileMenu({ file: entry, x: Math.max(8, Math.min(event.clientX - rect.left, rect.width - 202)), y: Math.max(8, Math.min(event.clientY - rect.top, rect.height - 340)) }); }} onDoubleClick={() => entry.type === 'directory' && void load(entry.path)}>
            <span className={`file-icon ${entry.type === 'directory' ? 'folder-icon' : ''}`}>{entry.type === 'directory' ? <Folder size={15}/> : <File size={15}/>}</span>
            <span className="file-name"><strong>{entry.name}</strong><small>{entry.type === 'directory' ? 'Directory' : formatBytes(entry.size)}</small></span>
            <span className="file-meta"><small>{entry.permissions ?? '—'}</small><small>{entry.owner ?? '—'}</small><small>{formatDate(entry.modifiedAt)}</small></span>
          </button>
        ))}
      </div>
      <div className="files-footer">
        <span>{filteredEntries.length} item{filteredEntries.length === 1 ? '' : 's'}</span>
        {pageCount > 1 && <span className="files-pagination"><button aria-label="Previous file page" disabled={page === 1} onClick={() => setPage(current => Math.max(1, current - 1))}><ChevronLeft size={13}/></button><b>{page}/{pageCount}</b><button aria-label="Next file page" disabled={page === pageCount} onClick={() => setPage(current => Math.min(pageCount, current + 1))}><ChevronRight size={13}/></button></span>}
      </div>
    </aside>
  );
}

function FileAccessModal({ kind, file, onCancel, onApply }: {
  kind: AccessModal;
  file: RemoteFile;
  onCancel: () => void;
  onApply: (kind: AccessModal, value: { mode: number; uid: number; gid: number }) => Promise<void>;
}) {
  const dialog = useRef<HTMLDialogElement>(null);
  const [bits, setBits] = useState(() => permissionsFromMode(file.permissions));
  const [uid, setUid] = useState(file.owner?.split(':')[0] ?? '');
  const [gid, setGid] = useState(file.owner?.split(':')[1] ?? '');
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    const element = dialog.current;
    if (!element) return;
    element.showModal();
    return () => { if (element.open) element.close(); };
  }, []);

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (busy) return;
    const ownerId = Number(uid);
    const groupId = Number(gid);
    if (kind === 'owner' && (!Number.isInteger(ownerId) || ownerId < 0 || !Number.isInteger(groupId) || groupId < 0)) return;
    setBusy(true);
    try { await onApply(kind, { mode: modeFromPermissions(bits), uid: ownerId, gid: groupId }); }
    finally { setBusy(false); }
  }

  return <dialog ref={dialog} className="session-dialog" onCancel={event => { event.preventDefault(); if (!busy) onCancel(); }}>
    <form className="session-modal access-modal" onSubmit={submit}>
      <div className="modal-head">
        <div><p className="eyebrow">REMOTE FILES</p><h2>{kind === 'permissions' ? 'Change permissions' : 'Change owner'}</h2></div>
        <button type="button" className="icon-button" aria-label="Close access form" disabled={busy} onClick={onCancel}>×</button>
      </div>
      <p className="access-target"><span>{file.name}</span><small>{file.path}</small></p>
      {kind === 'permissions' ? <>
        <div className="permission-summary"><Shield size={17}/><div><strong>Mode {modeFromPermissions(bits).toString(8).padStart(3, '0')}</strong><small>Choose what each access group can do.</small></div></div>
        <div className="permission-grid" role="group" aria-label="File permissions">
          <div className="permission-grid-head"><span>Access group</span><span>Read</span><span>Write</span><span>Execute</span></div>
          {(['owner', 'group', 'other'] as const).map(group => <div className="permission-grid-row" key={group}>
            <strong>{group === 'owner' ? 'Owner' : group === 'group' ? 'Group' : 'Others'}</strong>
            {(['read', 'write', 'execute'] as const).map(permission => <label key={permission} className="permission-check"><input type="checkbox" checked={bits[group][permission]} onChange={event => setBits({ ...bits, [group]: { ...bits[group], [permission]: event.target.checked } })}/><span>{permission[0].toUpperCase()}</span></label>)}
          </div>)}
        </div>
        <p className="access-hint">Octal mode is calculated automatically. Example: <code>755</code> allows owner write access and read/execute access for everyone else.</p>
      </> : <>
        <div className="owner-current"><span className="owner-avatar">u</span><div><small>Current owner</small><strong>{file.owner ?? 'Not reported by server'}</strong></div></div>
        <div className="field-row owner-fields"><label>UID<input type="number" min="0" value={uid} onChange={event => setUid(event.target.value)} required/></label><label>GID<input type="number" min="0" value={gid} onChange={event => setGid(event.target.value)} required/></label></div>
        <p className="access-hint">Use numeric Linux user and group IDs. Permission changes require the file owner or root privileges on the SSH server.</p>
      </>}
      <div className="modal-actions"><button type="button" className="cancel-button" disabled={busy} onClick={onCancel}>Cancel</button><button className="new-button" disabled={busy} type="submit">{busy ? 'Applying…' : 'Apply changes'}</button></div>
    </form>
  </dialog>;
}

type PermissionBits = Record<'owner' | 'group' | 'other', Record<'read' | 'write' | 'execute', boolean>>;
function permissionsFromMode(value?: string): PermissionBits {
  const mode = parseInt(value ?? '644', 8) || 0o644;
  return {
    owner: { read: Boolean(mode & 0o400), write: Boolean(mode & 0o200), execute: Boolean(mode & 0o100) },
    group: { read: Boolean(mode & 0o040), write: Boolean(mode & 0o020), execute: Boolean(mode & 0o010) },
    other: { read: Boolean(mode & 0o004), write: Boolean(mode & 0o002), execute: Boolean(mode & 0o001) },
  };
}
function modeFromPermissions(bits: PermissionBits): number {
  return (bits.owner.read ? 0o400 : 0) | (bits.owner.write ? 0o200 : 0) | (bits.owner.execute ? 0o100 : 0)
    | (bits.group.read ? 0o040 : 0) | (bits.group.write ? 0o020 : 0) | (bits.group.execute ? 0o010 : 0)
    | (bits.other.read ? 0o004 : 0) | (bits.other.write ? 0o002 : 0) | (bits.other.execute ? 0o001 : 0);
}

function joinPath(parent: string, name: string): string {
  return `${parent.replace(/\/$/, '')}/${name.replace(/^\//, '')}` || '/';
}

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function formatDate(value?: string): string {
  if (!value) return '—';
  return new Intl.DateTimeFormat('fa-IR-u-ca-persian', { dateStyle: 'short' }).format(new Date(value));
}
