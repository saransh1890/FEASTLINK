import { NextResponse } from 'next/server';
import { getSession, SessionUser } from './auth';
export async function requireUser(roles?: string[]) {
 const user = await getSession();
 if (!user) return { user: null, response: NextResponse.json({error:'Authentication required'}, {status:401}) };
 if (roles && !roles.includes(user.role)) return {user:null,response:NextResponse.json({error:'You do not have permission for this action'}, {status:403})};
 return {user, response:null};
}
export function errorResponse(error: unknown) { console.error(error); return NextResponse.json({error: error instanceof Error ? error.message : 'Something went wrong'}, {status:400}); }
