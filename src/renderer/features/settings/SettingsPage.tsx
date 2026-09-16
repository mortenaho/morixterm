import { useEffect, useState } from 'react';
import type { AppSettings } from '../../../../electron/contracts/settings';

export default function SettingsPage({ settings, onSave, compact = false }: {
  settings: AppSettings;
  onSave: (value: AppSettings) => Promise<void>;
  compact?: boolean;
}) {
  const [draft, setDraft] = useState(settings);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');

  useEffect(() => setDraft(settings), [settings]);

  return (
    <div className={compact ? 'settings-modal-content' : 'page settings-page'}>
      {!compact && <><p className="eyebrow">SETTINGS</p><h1>Preferences</h1></>}
      <form className="panel settings-form" onSubmit={async event => {
        event.preventDefault();
        setBusy(true);
        try {
          await onSave(draft);
          setMessage('Settings saved.');
        } catch (error) {
          setMessage(error instanceof Error ? error.message : 'Could not save settings.');
        } finally {
          setBusy(false);
        }
      }}>
        <label>Appearance
          <select value={draft.appearance} onChange={event => setDraft({ ...draft, appearance: event.target.value as AppSettings['appearance'] })}>
            <option value="dark">Dark</option>
            <option value="light">Light</option>
            <option value="system">System</option>
          </select>
        </label>
        <label>Font family
          <input value={draft.terminal.fontFamily} onChange={event => setDraft({ ...draft, terminal: { ...draft.terminal, fontFamily: event.target.value } })}/>
        </label>
        <div className="field-row">
          <label>Font size
            <input type="number" min={10} max={28} value={draft.terminal.fontSize} onChange={event => setDraft({ ...draft, terminal: { ...draft.terminal, fontSize: Number(event.target.value) } })}/>
          </label>
          <label>Scrollback
            <input type="number" min={100} max={50000} value={draft.terminal.scrollback} onChange={event => setDraft({ ...draft, terminal: { ...draft.terminal, scrollback: Number(event.target.value) } })}/>
          </label>
        </div>
        <label className="favorite-field">
          <input type="checkbox" checked={draft.terminal.cursorBlink} onChange={event => setDraft({ ...draft, terminal: { ...draft.terminal, cursorBlink: event.target.checked } })}/>
          Cursor blink
        </label>
        <div className="modal-actions">
          <button className="new-button" disabled={busy} type="submit">{busy ? 'Saving…' : 'Save settings'}</button>
        </div>
        {message && <p className="empty-state">{message}</p>}
      </form>
    </div>
  );
}
