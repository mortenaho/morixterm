import log from 'electron-log';

const secretPattern = /(password|passwd|secret|token|private[_-]?key)\s*[:=]\s*\S+/gi;
const commandLinePasswordPattern = /\/p:[^\s]+/gi;

export function redact(value: string): string {
  return value
    .replace(secretPattern, '$1=[REDACTED]')
    .replace(commandLinePasswordPattern, '/p:[REDACTED]');
}

log.transports.file.level = 'info';
log.transports.console.level = 'info';

export const logger = {
  info: (message: string) => log.info(redact(message)),
  warn: (message: string) => log.warn(redact(message)),
  error: (message: string) => log.error(redact(message)),
};
