import log from 'electron-log';

const secretPattern = /(password|passwd|secret|token|private[_-]?key)\s*[:=]\s*\S+/gi;

export function redact(value: string): string {
  return value.replace(secretPattern, '$1=[REDACTED]');
}

log.transports.file.level = 'info';
log.transports.console.level = 'info';

export const logger = {
  info: (message: string, ...args: unknown[]) => log.info(redact(message), ...args),
  warn: (message: string, ...args: unknown[]) => log.warn(redact(message), ...args),
  error: (message: string, ...args: unknown[]) => log.error(redact(message), ...args),
};
