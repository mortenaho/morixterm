import { useEffect, useRef, useState, type FormEvent } from 'react';
import { Laptop, Monitor, Plus, Save, Server, X } from 'lucide-react';
import { saveSessionSchema, type SaveSession, type Session } from '../../../../electron/contracts/sessions';

export default function SessionModal({
  initial,
  initialKind = 'SSH',
  onCancel,
  onSave,
}: {
  initial?: Session;
  initialKind?: Session['kind'];
  onCancel: () => void;
  onSave: (value: SaveSession) => Promise<void>;
}) {
  const dialog = useRef<HTMLDialogElement>(null);
  const submitting = useRef(false);
  const [busy, setBusy] = useState(false);
  const [error, onError] = useState('');
  const [kind, setKind] = useState(initial?.kind ?? initialKind);
  const [name, setName] = useState(initial?.name ?? '');
  const [host, setHost] = useState(initial?.host ?? '');
  const [port, setPort] = useState(String(initial?.port ?? (initialKind === 'RDP' ? 3389 : 22)));
  const [user, setUser] = useState(initial?.user ?? '');
  const [password, setPassword] = useState('');
  const [favorite, setFavorite] = useState(initial?.favorite ?? false);
  const [color, setColor] = useState(initial?.color ?? (initialKind === 'SSH' ? '#38d9c3' : initialKind === 'RDP' ? '#f8b84e' : '#a78bfa'));

  useEffect(() => {
    const previous = document.activeElement as HTMLElement | null;
    const element = dialog.current!;
    element.showModal();
    return () => {
      element.close();
      previous?.focus();
    };
  }, []);

  async function save(event: FormEvent) {
    event.preventDefault();
    if (submitting.current) return;
    const value = saveSessionSchema.safeParse({
      id: initial?.id,
      name,
      host: kind === 'LOCAL' ? 'localhost' : host,
      port: kind === 'LOCAL' ? undefined : Number(port),
      user,
      kind,
      platform: kind === 'RDP' ? 'WINDOWS' : 'LINUX',
      group: initial?.group ?? '',
      favorite,
      color,
      password: kind === 'LOCAL' ? undefined : password || undefined,
    });
    if (!value.success) {
      onError('Enter a name, host and username, and a port between 1 and 65535.');
      return;
    }
    submitting.current = true;
    setBusy(true);
    try {
      await onSave(value.data);
    } catch (cause) {
      onError(cause instanceof Error ? cause.message : 'Could not save the session. Please retry.');
    } finally {
      submitting.current = false;
      setBusy(false);
    }
  }

  return (
    <dialog ref={dialog} className="session-dialog" aria-labelledby="session-title" onCancel={event => {
      event.preventDefault();
      if (!busy) onCancel();
    }}>
      <form className="session-modal" noValidate onSubmit={save} aria-busy={busy}>
        <div className="modal-head">
          <div>
            <p className="eyebrow">{initial ? 'EDIT SESSION' : 'NEW CONNECTION'}</p>
            <h2 id="session-title">{initial ? 'Edit session' : 'Add a session'}</h2>
          </div>
          <button type="button" className="icon-button" aria-label="Close session form" disabled={busy} onClick={onCancel}><X size={18}/></button>
        </div>
        <fieldset disabled={busy} className="session-fields">
          <div className="type-tabs" role="group" aria-label="Session type">
            {(['SSH', 'RDP', 'LOCAL'] as const).map(value => (
              <button
                type="button"
                key={value}
                aria-pressed={kind === value}
                className={kind === value ? 'selected' : ''}
                onClick={() => {
                  if (value !== kind) {
                    setKind(value);
                    setPort(value === 'RDP' ? '3389' : '22');
                    setPassword('');
                  }
                }}
              >
                {value === 'SSH' ? <Server size={15}/> : value === 'RDP' ? <Monitor size={15}/> : <Laptop size={15}/>}
                {value === 'LOCAL' ? 'Local terminal' : value}
              </button>
            ))}
          </div>
          <label>Session name<input autoFocus value={name} maxLength={128} onChange={event => setName(event.target.value)} required/></label>
          {kind !== 'LOCAL' && (
            <div className="field-row">
              <label>Host<input value={host} maxLength={255} onChange={event => setHost(event.target.value)} required/></label>
              <label>Port<input type="number" min={1} max={65535} value={port} onChange={event => setPort(event.target.value)} required/></label>
            </div>
          )}
          <label>Username<input value={user} maxLength={128} autoComplete="username" onChange={event => setUser(event.target.value)} required/></label>
          {kind !== 'LOCAL' && (
            <label>Password
              <input
                type="password"
                value={password}
                maxLength={1000}
                autoComplete="new-password"
                onChange={event => setPassword(event.target.value)}
                placeholder={initial?.hasPassword ? 'Leave blank to keep saved password' : 'Optional'}
              />
            </label>
          )}
          <label className="color-field">Tab color<div><input type="color" value={color} onChange={event => setColor(event.target.value)}/><code>{color}</code></div></label>
          <label className="favorite-field"><input type="checkbox" checked={favorite} onChange={event => setFavorite(event.target.checked)}/> Favorite</label>
        </fieldset>
        <div className="modal-actions">
          <button type="button" className="cancel-button" disabled={busy} onClick={onCancel}><X size={14}/> Cancel</button>
          <button className="new-button" type="submit" disabled={busy}>
            {initial ? <Save size={16}/> : <Plus size={16}/>}
            {busy ? 'Saving…' : initial ? 'Save changes' : 'Add session'}
          </button>
        </div>
      </form>
      {error && (
        <div className="toast toast-error" role="alert">
          <span>{error}</span>
          <button type="button" className="icon-button" aria-label="Dismiss error" onClick={() => onError('')}><X size={16}/></button>
        </div>
      )}
    </dialog>
  );
}
