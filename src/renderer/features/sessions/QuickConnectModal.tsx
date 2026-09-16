import { useEffect, useRef, useState, type FormEvent } from 'react';
import { X } from 'lucide-react';

export type QuickConnectValue = {
  host: string;
  port: number;
  username: string;
  password?: string;
  save: boolean;
  name?: string;
};

export default function QuickConnectModal({
  onCancel,
  onConnect,
}: {
  onCancel: () => void;
  onConnect: (value: QuickConnectValue) => Promise<void>;
}) {
  const dialog = useRef<HTMLDialogElement>(null);
  const [host, setHost] = useState('');
  const [port, setPort] = useState('22');
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [save, setSave] = useState(true);
  const [name, setName] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    dialog.current?.showModal();
  }, []);

  async function submit(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError('');
    try {
      await onConnect({
        host,
        port: Number(port),
        username,
        password: password || undefined,
        save,
        name: name || `${username}@${host}`,
      });
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Connection failed');
      setBusy(false);
    }
  }

  return (
    <dialog ref={dialog} className="session-dialog" onCancel={event => { event.preventDefault(); if (!busy) onCancel(); }}>
      <form className="session-modal" onSubmit={submit}>
        <div className="modal-head">
          <div>
            <p className="eyebrow">QUICK CONNECT</p>
            <h2>SSH connection</h2>
          </div>
          <button type="button" className="icon-button" disabled={busy} onClick={onCancel}><X size={18}/></button>
        </div>
        <label>Host<input required value={host} onChange={event => setHost(event.target.value)} placeholder="192.168.1.10"/></label>
        <div className="field-row">
          <label>Username<input required value={username} onChange={event => setUsername(event.target.value)}/></label>
          <label>Port<input required type="number" min={1} max={65535} value={port} onChange={event => setPort(event.target.value)}/></label>
        </div>
        <label>Password<input type="password" value={password} onChange={event => setPassword(event.target.value)} placeholder="Optional if using agent later"/></label>
        <label className="favorite-field"><input type="checkbox" checked={save} onChange={event => setSave(event.target.checked)}/> Save session</label>
        {save && <label>Session name<input value={name} onChange={event => setName(event.target.value)} placeholder="Optional"/></label>}
        <div className="modal-actions">
          <button type="button" className="cancel-button" disabled={busy} onClick={onCancel}>Cancel</button>
          <button className="new-button" disabled={busy} type="submit">{busy ? 'Connecting…' : 'Connect'}</button>
        </div>
        {error && <p className="form-error" role="alert">{error}</p>}
      </form>
    </dialog>
  );
}
