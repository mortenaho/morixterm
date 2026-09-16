import { X } from 'lucide-react';
import { useEffect } from 'react';
import { useWorkspace } from '../stores/workspaceStore';

export default function Toasts() {
  const toasts = useWorkspace(state => state.toasts);
  const dismissToast = useWorkspace(state => state.dismissToast);

  useEffect(() => {
    const timers = toasts.map(toast => window.setTimeout(
      () => dismissToast(toast.id),
      toast.tone === 'error' ? 6000 : 4000,
    ));
    return () => timers.forEach(timer => window.clearTimeout(timer));
  }, [toasts, dismissToast]);

  return (
    <div className="toast-stack" aria-live="polite" aria-atomic="false">
      {toasts.map(toast => (
        <div key={toast.id} className={`toast ${toast.tone === 'error' ? 'toast-error' : ''}`} role="status">
          <div>
            <strong>{toast.title}</strong>
            <small>{toast.message}</small>
          </div>
          <button className="icon-button" aria-label="Dismiss" onClick={() => dismissToast(toast.id)}><X size={14}/></button>
        </div>
      ))}
    </div>
  );
}
