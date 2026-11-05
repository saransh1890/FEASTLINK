import {NextResponse} from 'next/server';import {clearSession,getSession} from '@/lib/auth';import {audit} from '@/lib/db';
export async function POST(){const u=await getSession();if(u)await audit('USER_LOGOUT',u.userId);clearSession();return NextResponse.json({ok:true});}
