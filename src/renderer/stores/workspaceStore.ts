import { create } from 'zustand';
import type { WorkspaceTab } from '../env';

type Toast = { id: string; title: string; message: string; tone?: 'info' | 'error' | 'success' };

type WorkspaceState = {
  sidebarCollapsed: boolean;
  activeNav: string;
  tabs: WorkspaceTab[];
  activeTabId: string;
  cols: number;
  rows: number;
  connectionLabel: string;
  toasts: Toast[];
  paletteOpen: boolean;
  toggleSidebar: () => void;
  setActiveNav: (nav: string) => void;
  openTab: (tab: WorkspaceTab) => void;
  closeTab: (id: string) => void;
  setActiveTab: (id: string) => void;
  moveTab: (id: string, beforeId: string) => void;
  updateTab: (id: string, patch: Partial<WorkspaceTab>) => void;
  setTerminalSize: (cols: number, rows: number) => void;
  setConnectionLabel: (label: string) => void;
  pushToast: (toast: Omit<Toast, 'id'>) => void;
  dismissToast: (id: string) => void;
  setPaletteOpen: (open: boolean) => void;
};

const homeTab: WorkspaceTab = { id: 'home', title: 'Home', kind: 'home' };

export const useWorkspace = create<WorkspaceState>((set, get) => ({
  sidebarCollapsed: false,
  activeNav: 'Home',
  tabs: [homeTab],
  activeTabId: 'home',
  cols: 120,
  rows: 32,
  connectionLabel: 'Ready',
  toasts: [],
  paletteOpen: false,
  toggleSidebar: () => set(state => ({ sidebarCollapsed: !state.sidebarCollapsed })),
  setActiveNav: nav => set({ activeNav: nav }),
  openTab: tab => {
    const existing = get().tabs.find(item => item.id === tab.id);
    if (existing) {
      set({ activeTabId: existing.id, activeNav: navFor(existing.kind) });
      return;
    }
    set(state => ({
      tabs: [...state.tabs, tab],
      activeTabId: tab.id,
      activeNav: navFor(tab.kind),
    }));
  },
  closeTab: id => {
    if (id === 'home') return;
    const { tabs, activeTabId } = get();
    const next = tabs.filter(tab => tab.id !== id);
    const fallback = next.find(tab => tab.id === activeTabId) ?? next[next.length - 1] ?? homeTab;
    set({ tabs: next.length ? next : [homeTab], activeTabId: fallback.id, activeNav: navFor(fallback.kind) });
  },
  setActiveTab: id => {
    const tab = get().tabs.find(item => item.id === id);
    if (!tab) return;
    set({ activeTabId: id, activeNav: navFor(tab.kind) });
  },
  moveTab: (id, beforeId) => set(state => {
    if (id === beforeId || id === 'home') return state;
    const moving = state.tabs.find(tab => tab.id === id);
    if (!moving) return state;
    const withoutMoving = state.tabs.filter(tab => tab.id !== id);
    const targetIndex = withoutMoving.findIndex(tab => tab.id === beforeId);
    if (targetIndex < 0) return state;
    withoutMoving.splice(targetIndex, 0, moving);
    return { tabs: withoutMoving };
  }),
  updateTab: (id, patch) => set(state => ({
    tabs: state.tabs.map(tab => (tab.id === id ? { ...tab, ...patch } : tab)),
  })),
  setTerminalSize: (cols, rows) => set({ cols, rows }),
  setConnectionLabel: label => set({ connectionLabel: label }),
  pushToast: toast => set(state => ({
    toasts: [...state.toasts, { ...toast, id: crypto.randomUUID() }].slice(-4),
  })),
  dismissToast: id => set(state => ({ toasts: state.toasts.filter(toast => toast.id !== id) })),
  setPaletteOpen: open => set({ paletteOpen: open }),
}));

function navFor(kind: WorkspaceTab['kind']): string {
  switch (kind) {
    case 'sessions': return 'Sessions';
    case 'settings': return 'Settings';
    case 'about': return 'About';
    case 'terminal':
    case 'ssh': return 'Terminal';
    case 'files': return 'Files';
    case 'snippets': return 'Snippets';
    default: return 'Home';
  }
}
