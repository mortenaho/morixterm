import keytar from 'keytar';

const SERVICE = 'MoriXterm';
const APP_LOCK_ACCOUNT = 'application:lock';
export const credentialKey = (sessionName: string) => `session:${sessionName}`;
export async function savePassword(sessionName: string, password: string) { if (password) await keytar.setPassword(SERVICE, credentialKey(sessionName), password); }
export async function getPassword(sessionName: string) { return keytar.getPassword(SERVICE, credentialKey(sessionName)); }
export async function deletePassword(sessionName: string) { await keytar.deletePassword(SERVICE, credentialKey(sessionName)); }
export async function saveAppLockPassword(password: string) { await keytar.setPassword(SERVICE, APP_LOCK_ACCOUNT, password); }
export async function getAppLockPassword() { return keytar.getPassword(SERVICE, APP_LOCK_ACCOUNT); }
