import { useEffect, useRef, useState } from 'react';
import { FitAddon } from '@xterm/addon-fit';
import { SearchAddon } from '@xterm/addon-search';
import { Unicode11Addon } from '@xterm/addon-unicode11';
import { WebLinksAddon } from '@xterm/addon-web-links';
import { WebglAddon } from '@xterm/addon-webgl';
import { Terminal } from '@xterm/xterm';
import '@xterm/xterm/css/xterm.css';
import type { AppSettings } from '../../../../electron/contracts/settings';
import type { Session } from '../../../../electron/contracts/sessions';
import { useWorkspace } from '../../stores/workspaceStore';
import { writeWelcomeBanner } from './welcomeBanner';

type Props = {
  transport: 'pty' | 'ssh';
  transportId: string;
  settings: AppSettings;
  session?: Session;
  onExit?: () => void;
};

export default function TerminalView({ transport, transportId, settings, session, onExit }: Props) {
  const hostRef = useRef<HTMLDivElement>(null);
  const terminalRef = useRef<Terminal | null>(null);
  const [contextMenu, setContextMenu] = useState<{ x: number; y: number } | null>(null);
  const setTerminalSize = useWorkspace(state => state.setTerminalSize);
  const setConnectionLabel = useWorkspace(state => state.setConnectionLabel);

  useEffect(() => {
    const host = hostRef.current;
    if (!host) return;
    let cancelled = false;
    let welcomeDone = false;
    const pending: string[] = [];

    const term = new Terminal({
      cursorBlink: settings.terminal.cursorBlink,
      fontFamily: settings.terminal.fontFamily,
      fontSize: settings.terminal.fontSize,
      lineHeight: settings.terminal.lineHeight,
      scrollback: settings.terminal.scrollback,
      theme: {
        background: '#242424',
        foreground: '#dedede',
        cursor: '#70d7c4',
        selectionBackground: '#454545',
      },
      allowProposedApi: true,
    });
    const fit = new FitAddon();
    const search = new SearchAddon();
    const links = new WebLinksAddon();
    const unicode = new Unicode11Addon();
    term.loadAddon(fit);
    term.loadAddon(search);
    term.loadAddon(links);
    term.loadAddon(unicode);
    term.unicode.activeVersion = '11';
    term.open(host);
    terminalRef.current = term;
    try {
      term.loadAddon(new WebglAddon());
    } catch {
      // WebGL is an optimization; the canvas renderer remains the safe fallback.
    }

    const api = transport === 'pty' ? window.mori.pty : window.mori.ssh;
    const write = (data: string) => api.write({ id: transportId, data });
    const resize = (cols: number, rows: number) => api.resize({ id: transportId, cols, rows });

    const applyFit = () => {
      try {
        fit.fit();
        resize(term.cols, term.rows);
        setTerminalSize(term.cols, term.rows);
      } catch {
        /* terminal may not be visible yet */
      }
    };

    const flushShellOutput = () => {
      welcomeDone = true;
      for (const chunk of pending) term.write(chunk);
      pending.length = 0;
    };

    const showWelcome = (version: string, platform: string) => {
      if (cancelled) return;
      // Fit first: the ASCII frame must be measured against the actual pane,
      // otherwise xterm may wrap it when the initial default grid is replaced.
      applyFit();
      writeWelcomeBanner(term, {
        version,
        platform,
        transport,
        sessionName: session?.name,
        host: session?.host,
        user: session?.user,
        port: session?.port,
      });
      flushShellOutput();
    };

    void window.mori.appInfo()
      .then(info => showWelcome(info.version, info.platform))
      .catch(() => showWelcome('0.1.0', navigator.platform || 'desktop'));

    const onData = api.onData(payload => {
      if (payload.id !== transportId) return;
      const text = decodeBase64(payload.data);
      if (!welcomeDone) pending.push(text);
      else term.write(text);
    });
    const onClosed = api.onClosed(payload => {
      if (payload.id !== transportId) return;
      term.writeln('\r\n\x1b[31m[session closed]\x1b[0m');
      setConnectionLabel('Disconnected');
      onExit?.();
    });

    const disposable = term.onData(data => write(data));
    const copySelection = async () => {
      const selection = term.getSelection();
      if (selection) await navigator.clipboard.writeText(selection);
      setContextMenu(null);
    };
    const pasteClipboard = async () => {
      const value = await navigator.clipboard.readText();
      if (value) write(value);
      setContextMenu(null);
    };
    term.attachCustomKeyEventHandler(event => {
      const modifier = event.ctrlKey || event.metaKey;
      if (modifier && event.shiftKey && event.key.toLowerCase() === 'c') { void copySelection(); return false; }
      if (modifier && event.shiftKey && event.key.toLowerCase() === 'v') { void pasteClipboard(); return false; }
      return true;
    });
    const onContextMenu = (event: MouseEvent) => {
      event.preventDefault();
      setContextMenu({ x: event.offsetX, y: event.offsetY });
    };
    host.addEventListener('contextmenu', onContextMenu);

    const onWheel = (event: WheelEvent) => {
      if (!event.ctrlKey) return;
      event.preventDefault();
      const step = event.deltaY < 0 ? 1 : -1;
      const current = term.options.fontSize ?? settings.terminal.fontSize;
      const next = Math.min(28, Math.max(10, current + step));
      if (next === current) return;
      term.options.fontSize = next;
      applyFit();
    };
    host.addEventListener('wheel', onWheel, { passive: false });

    const observer = new ResizeObserver(() => applyFit());
    observer.observe(host);
    requestAnimationFrame(applyFit);
    term.focus();
    setConnectionLabel(transport === 'pty' ? 'Local terminal' : 'SSH connected');

    return () => {
      cancelled = true;
      onData();
      onClosed();
      disposable.dispose();
      host.removeEventListener('contextmenu', onContextMenu);
      host.removeEventListener('wheel', onWheel);
      observer.disconnect();
      if (transport === 'pty') window.mori.pty.stop(transportId);
      else window.mori.ssh.disconnect(transportId);
      term.dispose();
      terminalRef.current = null;
    };
  // Keep the transport lifecycle stable. Settings and callback objects can change
  // during normal renderer updates; rerunning this effect would disconnect SSH.
  // A transport is torn down only when its kind or opaque id actually changes.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [transport, transportId]);

  return <div className="terminal-host" ref={hostRef} onClick={() => contextMenu && setContextMenu(null)}>
    {contextMenu && <div className="terminal-context-menu" style={{ left: contextMenu.x, top: contextMenu.y }} onClick={event => event.stopPropagation()}>
      <button onClick={() => { const term = terminalRef.current; if (term) void navigator.clipboard.writeText(term.getSelection()); setContextMenu(null); }}>Copy</button>
      <button onClick={() => { const term = terminalRef.current; if (term) term.selectAll(); }}>Select all</button>
      <button onClick={() => { const termApi = transport === 'pty' ? window.mori.pty : window.mori.ssh; void navigator.clipboard.readText().then(value => { if (value) termApi.write({ id: transportId, data: value }); }); setContextMenu(null); }}>Paste</button>
      <button onClick={() => { terminalRef.current?.clear(); setContextMenu(null); }}>Clear terminal</button>
    </div>}
  </div>;
}

function decodeBase64(value: string): string {
  const binary = atob(value);
  const bytes = Uint8Array.from(binary, char => char.charCodeAt(0));
  return new TextDecoder().decode(bytes);
}
