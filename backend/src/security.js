import crypto from 'node:crypto';
export const hash = value => crypto.createHash('sha256').update(value).digest('hex');
export const otp = () => String(crypto.randomInt(100000, 1000000));
export const opaque = () => crypto.randomBytes(32).toString('base64url');
export function publicUser(u) { return {id:u.id,email:u.email,username:u.username,name:u.name,role:u.role}; }
