import { Command, Plus, Search, SquareTerminal } from 'lucide-react';
import { useWorkspace } from '../stores/workspaceStore';

type CommandItem = { id: string; label: string; run: () => void };

export default function CommandPalette({ commands }: { commands: CommandItem[] }) {
  const open = useWorkspace(state => state.paletteOpen);
  const setPaletteOpen = useWorkspace(state => state.setPaletteOpen);
  if (!open) return null;

  return (
    <div className="overlay" onClick={() => setPaletteOpen(false)}>
      <div className="palette" onClick={event => event.stopPropagation()}>
        <div className="palette-input">
          <Search size={18}/>
          <input autoFocus placeholder="Search commands…" onKeyDown={event => {
            if (event.key === 'Escape') setPaletteOpen(false);
          }}/>
          <kbd>ESC</kbd>
        </div>
        {commands.map(command => (
          <button key={command.id} onClick={() => { setPaletteOpen(false); command.run(); }}>
            <span className="palette-icon">
              {command.id.includes('terminal') ? <SquareTerminal size={16}/> : command.id.includes('ssh') ? <Plus size={16}/> : <Command size={16}/>}
            </span>
            {command.label}
          </button>
        ))}
      </div>
    </div>
  );
}
