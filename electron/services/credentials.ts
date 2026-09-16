import keytar from 'keytar';

const SERVICE = 'MoriXterm';
export const credentialKey = (sessionName: string) => `session:${sessionName}`;
export async function savePassword(sessionName: string, password: string) { if (password) await keytar.setPassword(SERVICE, credentialKey(sessionName), password); }
export async function getPassword(sessionName: string) { return keytar.getPassword(SERVICE, credentialKey(sessionName)); }
export async function deletePassword(sessionName: string) { await keytar.deletePassword(SERVICE, credentialKey(sessionName)); }
