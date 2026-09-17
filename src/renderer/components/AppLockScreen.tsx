import { useEffect, useRef, useState } from 'react';
import { LockKeyhole, UnlockKeyhole } from 'lucide-react';

export default function AppLockScreen({ onUnlock, onError }: {
  onUnlock: (password: string) => Promise<boolean>;
  onError: (message: string) => void;
}) {
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const input = useRef<HTMLInputElement>(null);

  useEffect(() => { input.current?.focus(); }, []);

  return (
    <div className="app-lock-screen" role="dialog" aria-modal="true" aria-labelledby="app-lock-title">
      <form className="app-lock-card" onSubmit={async event => {
        event.preventDefault();
        if (!password || busy) return;
        setBusy(true);
        const unlocked = await onUnlock(password);
        setBusy(false);
        if (!unlocked) {
          setPassword('');
          onError('The password is incorrect.');
          requestAnimationFrame(() => input.current?.focus());
        }
      }}>
        <div className="app-lock-icon"><LockKeyhole size={28}/></div>
        <p className="eyebrow">MORIXTERM SECURITY</p>
        <h2 id="app-lock-title">Workspace locked</h2>
        <p>Your sessions are still running securely in the background.</p>
        <label>Password
          <input ref={input} type="password" autoComplete="current-password" value={password} onChange={event => setPassword(event.target.value)}/>
        </label>
        <button className="new-button" type="submit" disabled={busy || !password}>
          <UnlockKeyhole size={15}/>{busy ? 'Unlocking…' : 'Unlock workspace'}
        </button>
      </form>
    </div>
  );
}
