declare module 'ssh2' {
  export type AlgorithmList = string[] | {
    append?: Array<string | RegExp>;
    prepend?: Array<string | RegExp>;
    remove?: Array<string | RegExp>;
  };
  export interface ConnectConfig {
    host: string;
    port: number;
    username: string;
    password?: string;
    privateKey?: string;
    readyTimeout?: number;
    keepaliveInterval?: number;
    tryKeyboard?: boolean;
    hostHash?: string;
    hostVerifier?: (key: string, callback: (verified: boolean) => void) => void;
    algorithms?: {
      kex?: AlgorithmList;
      cipher?: AlgorithmList;
      serverHostKey?: AlgorithmList;
      hmac?: AlgorithmList;
    };
  }
  export interface ClientChannel {
    on(event: string, listener: (...args: any[]) => void): this;
    write(data: string | Buffer): void;
    end(): void;
    setWindow(rows: number, cols: number, height: number, width: number): void;
  }
  export interface SftpAttrs { mode?: number; size?: number; mtime?: number; uid?: number; gid?: number; }
  export interface SftpFile { filename: string; attrs: SftpAttrs; }
  export interface Sftp {
    readdir(path: string, callback: (error: Error | undefined, entries: SftpFile[]) => void): void;
    fastPut(localPath: string, remotePath: string, options: { step?: (transferred: number, chunk: number, total: number) => void }, callback: (error?: Error) => void): void;
    fastGet(remotePath: string, localPath: string, options: { step?: (transferred: number, chunk: number, total: number) => void }, callback: (error?: Error) => void): void;
    mkdir(path: string, callback: (error?: Error) => void): void;
    rename(path: string, newPath: string, callback: (error?: Error) => void): void;
    unlink(path: string, callback: (error?: Error) => void): void;
    rmdir(path: string, callback: (error?: Error) => void): void;
    chmod(path: string, mode: number, callback: (error?: Error) => void): void;
    chown(path: string, uid: number, gid: number, callback: (error?: Error) => void): void;
  }
  export class Client {
    on(event: string, listener: (...args: any[]) => void): this;
    connect(config: ConnectConfig): this;
    shell(options: { term: string; cols: number; rows: number }, callback: (error: Error | undefined, channel: ClientChannel) => void): void;
    sftp(callback: (error: Error | undefined, sftp: Sftp) => void): void;
    exec(command: string, callback: (error: Error | undefined, channel: ClientChannel) => void): void;
    end(): void;
  }
}

declare module 'node-pty' {
  export interface IPty {
    pid: number;
    onData(callback: (data: string) => void): void;
    onExit(callback: (event: { exitCode: number; signal?: number }) => void): void;
    write(data: string): void;
    resize(cols: number, rows: number): void;
    kill(): void;
  }
  export function spawn(
    file: string,
    args: string[],
    options: { name: string; cols: number; rows: number; cwd: string; env: Record<string, string | undefined> },
  ): IPty;
}

declare module 'keytar' {
  const keytar: {
    setPassword(service: string, account: string, password: string): Promise<void>;
    getPassword(service: string, account: string): Promise<string | null>;
    deletePassword(service: string, account: string): Promise<boolean>;
  };
  export default keytar;
}

declare module 'electron-log' {
  const log: {
    transports: { file: { level: string }; console: { level: string } };
    info: (...args: unknown[]) => void;
    warn: (...args: unknown[]) => void;
    error: (...args: unknown[]) => void;
  };
  export default log;
}
