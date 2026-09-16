import { Laptop, Monitor, Server, SquareTerminal, X } from 'lucide-react';
import { useState } from 'react';
import { useWorkspace } from '../stores/workspaceStore';
import type { WorkspaceTab } from '../env';

function iconFor(tab: WorkspaceTab) {
  if (tab.kind === 'ssh') return <Server size={13}/>;
  if (tab.kind === 'rdp') return <Monitor size={13}/>;
  if (tab.kind === 'terminal') return <SquareTerminal size={13}/>;
  if (tab.kind === 'home') return <Laptop size={13}/>;
  return <SquareTerminal size={13}/>;
}

export default function TabBar({ onCloseTab }: { onCloseTab?: (id: string) => void }) {
  const tabs = useWorkspace(state => state.tabs);
  const activeTabId = useWorkspace(state => state.activeTabId);
  const setActiveTab = useWorkspace(state => state.setActiveTab);
  const closeTab = useWorkspace(state => state.closeTab);
  const moveTab = useWorkspace(state => state.moveTab);
  const [draggedId, setDraggedId] = useState<string | null>(null);

  return (
    <div className="tabbar">
      {tabs.map(tab => (
        <div
          key={tab.id}
          className={`tab ${activeTabId === tab.id ? 'active' : ''} ${tab.session?.color ? 'tab-accented' : ''}`}
          style={tab.session?.color ? { borderTopColor: tab.session.color } : undefined}
          draggable={tab.id !== 'home'}
          onDragStart={event => {
            setDraggedId(tab.id);
            event.dataTransfer.effectAllowed = 'move';
            event.dataTransfer.setData('text/plain', tab.id);
          }}
          onDragOver={event => {
            if (draggedId && draggedId !== tab.id) event.preventDefault();
          }}
          onDrop={event => {
            event.preventDefault();
            const sourceId = event.dataTransfer.getData('text/plain') || draggedId;
            if (sourceId) moveTab(sourceId, tab.id);
            setDraggedId(null);
          }}
          onDragEnd={() => setDraggedId(null)}
          onAuxClick={event => {
            if (event.button !== 1 || tab.id === 'home') return;
            event.preventDefault();
            (onCloseTab ?? closeTab)(tab.id);
          }}
        >
          <button className="tab-main" onClick={() => setActiveTab(tab.id)}>
            {iconFor(tab)}
            <span>{tab.title}</span>
            {tab.status && <i className={`tab-status ${tab.status}`}/>}
          </button>
          {tab.id !== 'home' && (
            <button className="tab-close" aria-label={`Close ${tab.title}`} onClick={() => (onCloseTab ?? closeTab)(tab.id)}>
              <X size={12}/>
            </button>
          )}
        </div>
      ))}
    </div>
  );
}
