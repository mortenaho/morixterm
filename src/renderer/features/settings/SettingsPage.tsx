import { useEffect, useState } from 'react';
import { Check, DatabaseBackup, Database, KeyRound, Palette, Save, ShieldCheck } from 'lucide-react';
import Swal from 'sweetalert2';
import type { AppSettings } from '../../../../electron/contracts/settings';

type SettingsTab = 'appearance' | 'security' | 'data';

export default function SettingsPage({ settings, onSave, lockConfigured, onSetLockPassword, onNotice, onError, compact = false }: {
  settings: AppSettings;
  onSave: (value: AppSettings) => Promise<void>;
  lockConfigured: boolean;
  onSetLockPassword: (currentPassword: string | undefined, newPassword: string) => Promise<boolean>;
  onNotice: (title: string, message: string) => void;
  onError: (title: string, message: string) => void;
  compact?: boolean;
}) {
  const [draft, setDraft] = useState(settings);
  const [busy, setBusy] = useState(false);
  const [passwordBusy, setPasswordBusy] = useState(false);
  const [currentPassword, setCurrentPassword] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [activeTab, setActiveTab] = useState<SettingsTab>('appearance');

  useEffect(() => setDraft(settings), [settings]);

  const saveSettings = async () => {
    setBusy(true);
    try {
      await onSave(draft);
      onNotice('Settings saved', 'Your preferences were updated.');
    } catch (error) {
      onError('Settings failed', error instanceof Error ? error.message : 'Could not save settings.');
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className={compact ? 'settings-modal-content' : 'page settings-page'}>
      {!compact && <><p className="eyebrow">SETTINGS</p><h1>Preferences</h1></>}
      {compact && <div className="settings-tabs" role="tablist" aria-label="Settings sections" onKeyDown={event => {
        const tabs: SettingsTab[] = ['appearance', 'security', 'data'];
        const currentIndex = tabs.indexOf(activeTab);
        const nextIndex = event.key === 'ArrowRight' ? (currentIndex + 1) % tabs.length
          : event.key === 'ArrowLeft' ? (currentIndex - 1 + tabs.length) % tabs.length
          : event.key === 'Home' ? 0 : event.key === 'End' ? tabs.length - 1 : -1;
        if (nextIndex < 0) return;
        event.preventDefault();
        const nextTab = tabs[nextIndex];
        setActiveTab(nextTab);
        requestAnimationFrame(() => document.getElementById(`settings-tab-${nextTab}`)?.focus());
      }}>
        <button id="settings-tab-appearance" type="button" role="tab" tabIndex={activeTab === 'appearance' ? 0 : -1} aria-selected={activeTab === 'appearance'} aria-controls="settings-appearance" className={activeTab === 'appearance' ? 'active' : ''} onClick={() => setActiveTab('appearance')}><Palette size={15}/><span>Appearance</span></button>
        <button id="settings-tab-security" type="button" role="tab" tabIndex={activeTab === 'security' ? 0 : -1} aria-selected={activeTab === 'security'} aria-controls="settings-security" className={activeTab === 'security' ? 'active' : ''} onClick={() => setActiveTab('security')}><ShieldCheck size={15}/><span>Security</span></button>
        <button id="settings-tab-data" type="button" role="tab" tabIndex={activeTab === 'data' ? 0 : -1} aria-selected={activeTab === 'data'} aria-controls="settings-data" className={activeTab === 'data' ? 'active' : ''} onClick={() => setActiveTab('data')}><Database size={15}/><span>Data</span></button>
      </div>}
      {(!compact || activeTab === 'appearance') && <form id="settings-appearance" role={compact ? 'tabpanel' : undefined} aria-labelledby={compact ? 'settings-tab-appearance' : undefined} className="panel settings-form settings-tab-panel" onSubmit={async event => {
        event.preventDefault();
        await saveSettings();
      }}>
        <div className="settings-section-head">
          <span className="settings-section-icon"><Palette size={17}/></span>
          <div><h3>Appearance & terminal</h3><p>Customize the workspace and terminal display.</p></div>
        </div>
        <div className="settings-section-body">
          <label>Theme
            <select value={draft.appearance} onChange={event => setDraft({ ...draft, appearance: event.target.value as AppSettings['appearance'] })}>
              <option value="dark">Dark</option>
              <option value="light">Light</option>
              <option value="system">System</option>
            </select>
          </label>
          <label>Font family
            <input value={draft.terminal.fontFamily} onChange={event => setDraft({ ...draft, terminal: { ...draft.terminal, fontFamily: event.target.value } })}/>
          </label>
          <div className="field-row settings-number-row">
            <label>Font size
              <input type="number" min={10} max={28} value={draft.terminal.fontSize} onChange={event => setDraft({ ...draft, terminal: { ...draft.terminal, fontSize: Number(event.target.value) } })}/>
            </label>
            <label>Scrollback lines
              <input type="number" min={100} max={50000} value={draft.terminal.scrollback} onChange={event => setDraft({ ...draft, terminal: { ...draft.terminal, scrollback: Number(event.target.value) } })}/>
            </label>
          </div>
          <label className="settings-check-row">
            <input type="checkbox" checked={draft.terminal.cursorBlink} onChange={event => setDraft({ ...draft, terminal: { ...draft.terminal, cursorBlink: event.target.checked } })}/>
            <span className="settings-check-mark" aria-hidden="true"><Check size={13}/></span>
            <span><strong>Cursor blink</strong><small>Animate the text cursor inside terminal sessions.</small></span>
          </label>
        </div>
        <div className="settings-section-actions">
          <button className="new-button" disabled={busy} type="submit"><Save size={14}/>{busy ? 'Saving…' : 'Save settings'}</button>
        </div>
      </form>}
      {compact && activeTab === 'security' && <div id="settings-security" role="tabpanel" aria-labelledby="settings-tab-security" className="panel settings-form settings-tab-panel">
        <div className="settings-section-head">
          <span className="settings-section-icon"><ShieldCheck size={17}/></span>
          <div><h3>Application security</h3><p>{lockConfigured ? 'Manage automatic locking or change your unlock password.' : 'Set a password to enable manual and automatic locking.'}</p></div>
        </div>
        <div className="settings-section-body settings-password-grid">
          <label className="settings-full-row">Auto-lock after inactivity
            <div className="settings-input-suffix">
              <input type="number" min={0} max={240} value={draft.security.autoLockMinutes} onChange={event => setDraft({ ...draft, security: { autoLockMinutes: Number(event.target.value) } })}/>
              <span>minutes</span>
            </div>
            <small>Set to 0 to disable automatic locking. Manual lock remains available.</small>
          </label>
          {lockConfigured && <label className="settings-full-row">Current password
            <input type="password" autoComplete="current-password" value={currentPassword} onChange={event => setCurrentPassword(event.target.value)}/>
          </label>}
          <label>New password
            <input type="password" minLength={4} maxLength={256} autoComplete="new-password" value={newPassword} onChange={event => setNewPassword(event.target.value)}/>
          </label>
          <label>Confirm new password
            <input type="password" minLength={4} maxLength={256} autoComplete="new-password" value={confirmPassword} onChange={event => setConfirmPassword(event.target.value)}/>
          </label>
        </div>
        <div className="settings-section-actions settings-security-actions">
          <button type="button" className="cancel-button" disabled={busy} onClick={() => void saveSettings()}><Save size={14}/>{busy ? 'Saving…' : 'Save auto-lock'}</button>
          <button type="button" className="new-button" disabled={passwordBusy || newPassword.length < 4} onClick={async () => {
          if (newPassword !== confirmPassword) { onError('Password mismatch', 'The new passwords do not match.'); return; }
          setPasswordBusy(true);
          const saved = await onSetLockPassword(lockConfigured ? currentPassword : undefined, newPassword);
          setPasswordBusy(false);
          if (saved) {
            setCurrentPassword(''); setNewPassword(''); setConfirmPassword('');
            onNotice('Password saved', 'Application lock is ready.');
          }
        }}><KeyRound size={14}/>{passwordBusy ? 'Saving…' : lockConfigured ? 'Change password' : 'Set lock password'}</button>
        </div>
      </div>}
      {compact && activeTab === 'data' && <div id="settings-data" role="tabpanel" aria-labelledby="settings-tab-data" className="panel settings-form settings-tab-panel">
        <div className="settings-section-head">
          <span className="settings-section-icon"><Database size={17}/></span>
          <div><h3>Data protection</h3><p>Create a portable SQLite backup before upgrading or moving MoriXterm.</p></div>
        </div>
        <div className="settings-section-actions settings-section-actions-split"><button type="button" className="new-button" onClick={async () => {
          const result = await window.mori.database.backup();
          if (result.ok) onNotice('Backup created', result.path ?? 'Database backup completed.');
          else onError('Backup failed', result.message ?? 'Could not create the backup.');
        }}><DatabaseBackup size={14}/> Backup database</button>
        <button type="button" className="cancel-button" onClick={async () => {
          const confirmation = await Swal.fire({
            title: 'Restore database?',
            text: 'The current database will be backed up and replaced. MoriXterm will restart.',
            icon: 'warning', showCancelButton: true, confirmButtonText: 'Restore and restart',
            cancelButtonText: 'Cancel', reverseButtons: true, focusCancel: true,
          });
          if (!confirmation.isConfirmed) return;
          const result = await window.mori.database.restore();
          if (!result.ok) onError('Restore failed', result.message ?? 'Could not restore the database.');
        }}><Database size={14}/> Restore database</button></div>
      </div>}
    </div>
  );
}
