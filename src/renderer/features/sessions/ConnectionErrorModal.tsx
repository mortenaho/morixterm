import { useEffect, useRef } from 'react';
import { X } from 'lucide-react';

export default function ConnectionErrorModal({
  host,
  reason,
  onRetry,
  onEdit,
  onClose,
}: {
  host: string;
  reason: string;
  onRetry?: () => void;
  onEdit?: () => void;
  onClose: () => void;
}) {
  const dialog = useRef<HTMLDialogElement>(null);
  useEffect(() => { dialog.current?.showModal(); }, []);

  return (
    <dialog ref={dialog} className="session-dialog" onCancel={event => { event.preventDefault(); onClose(); }}>
      <div className="session-modal">
        <div className="modal-head">
          <div>
            <p className="eyebrow">CONNECTION FAILED</p>
            <h2>Could not connect</h2>
          </div>
          <button type="button" className="icon-button" onClick={onClose}><X size={18}/></button>
        </div>
        <p className="hero-copy"><strong>Host:</strong> {host}</p>
        <p className="form-error"><strong>Reason:</strong> {reason}</p>
        <div className="modal-actions">
          {onRetry && <button className="new-button" type="button" onClick={onRetry}>Retry</button>}
          {onEdit && <button className="cancel-button" type="button" onClick={onEdit}>Edit session</button>}
          <button className="cancel-button" type="button" onClick={onClose}>Close</button>
        </div>
      </div>
    </dialog>
  );
}
