import type { SVGProps } from 'react';

export default function PlatformIcon({ platform, size, ...props }: { platform: 'LINUX' | 'WINDOWS'; size?: number } & SVGProps<SVGSVGElement>) {
  const svgProps = { width: size, height: size, ...props };
  if (platform === 'WINDOWS') {
    return <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true" {...svgProps}>
      <path d="M3 4.6 10.2 3.5v8H3V4.6Zm8.2-1.25L21 2v9.5h-9.8v-8.15ZM3 12.9h7.2v8L3 19.8v-6.9Zm8.2 0H21V22l-9.8-1.35V12.9Z"/>
    </svg>;
  }
  return <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true" {...svgProps}>
    <path d="M12 2.2c-2.8 0-4.8 2.2-4.8 5.1 0 1.3.5 2.5 1.2 3.4-1.8 1.1-3 3.2-3 5.7 0 3.5 2.9 5.4 6.6 5.4s6.6-1.9 6.6-5.4c0-2.5-1.2-4.6-3-5.7.7-.9 1.2-2.1 1.2-3.4 0-2.9-2-5.1-4.8-5.1Zm-2.2 5.2c.5-.6 1.2-.9 2.2-.9s1.7.3 2.2.9c-.5.3-1.2.5-2.2.5s-1.7-.2-2.2-.5Zm-1 7.1c-.7 0-1.2-.5-1.2-1.1s.5-1.1 1.2-1.1 1.2.5 1.2 1.1-.5 1.1-1.2 1.1Zm6.4 0c-.7 0-1.2-.5-1.2-1.1s.5-1.1 1.2-1.1 1.2.5 1.2 1.1-.5 1.1-1.2 1.1Zm-5.5 3.1c.8.5 2.8.5 4.6 0-.5 1.1-1.2 1.6-2.3 1.6s-1.8-.5-2.3-1.6Z"/>
  </svg>;
}
