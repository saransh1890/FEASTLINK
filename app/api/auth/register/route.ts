import { NextRequest, NextResponse } from 'next/server';
import bcrypt from 'bcryptjs';
import { pool, audit } from '@/lib/db';
import { createSession } from '@/lib/auth';
export async function POST(req: NextRequest) {
 try {
  const b=await req.json(); const {name,email,phone,password,role,shelterName,location,contactPerson,residents,foodPreference}=b;
  if(!name||!email||!phone||!password||password.length<8||!['ORGANIZER','SHELTER_ADMIN'].includes(role)) return NextResponse.json({error:'Complete all required fields. Password must be at least 8 characters.'},{status:400});
  const conn=await pool.getConnection();
  try { await conn.beginTransaction();
   const [r]:any=await conn.execute('INSERT INTO users(name,email,phone,password,role) VALUES(?,?,?,?,?)',[name,email.toLowerCase(),phone,await bcrypt.hash(password,12),role]);
   let shelterId=null;
   if(role==='SHELTER_ADMIN') { if(!shelterName||!location||!contactPerson||!residents) throw new Error('Shelter details are required');
    const [s]:any=await conn.execute('INSERT INTO shelter_homes(user_id,shelter_name,location,contact_person,phone,number_of_residents,food_preference) VALUES(?,?,?,?,?,?,?)',[r.insertId,shelterName,location,contactPerson,phone,Number(residents),foodPreference||'Any']); shelterId=s.insertId;
   }
   await conn.commit(); const user={userId:r.insertId,name,email:email.toLowerCase(),role,shelterId}; await createSession(user); await audit('USER_REGISTERED',r.insertId,{role}); return NextResponse.json({user},{status:201});
  } catch(e){await conn.rollback(); throw e;} finally{conn.release();}
 } catch(e:any){return NextResponse.json({error:e.code==='ER_DUP_ENTRY'?'An account with this email already exists':e.message||'Registration failed'},{status:400});}
}
