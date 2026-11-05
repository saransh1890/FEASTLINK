import { SignJWT, jwtVerify } from 'jose';
import { cookies } from 'next/headers';
const secret = new TextEncoder().encode(process.env.JWT_SECRET || 'development-only-change-this-secret-32');
export type SessionUser = { userId: number; name: string; email: string; role: 'ORGANIZER'|'SHELTER_ADMIN'|'ADMIN'; shelterId?: number|null };
export async function createSession(user: SessionUser) {
 const token = await new SignJWT(user as any).setProtectedHeader({alg:'HS256'}).setIssuedAt().setExpirationTime('7d').sign(secret);
 cookies().set('feastlink_session', token, {httpOnly:true, secure:process.env.NODE_ENV==='production', sameSite:'lax', path:'/', maxAge:60*60*24*7});
}
export async function getSession(): Promise<SessionUser|null> {
 const token = cookies().get('feastlink_session')?.value; if(!token) return null;
 try { const {payload}=await jwtVerify(token,secret); return payload as unknown as SessionUser; } catch { return null; }
}
export function clearSession(){ cookies().delete('feastlink_session'); }
