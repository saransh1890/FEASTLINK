import mysql from 'mysql2/promise';
import { MongoClient } from 'mongodb';

const globalForDb = globalThis as unknown as { mysqlPool?: mysql.Pool; mongoClient?: MongoClient };
export const pool = globalForDb.mysqlPool ?? mysql.createPool({
  host: process.env.MYSQL_HOST || 'localhost', port: Number(process.env.MYSQL_PORT || 3306),
  user: process.env.MYSQL_USER || 'root', password: process.env.MYSQL_PASSWORD || '',
  database: process.env.MYSQL_DATABASE || 'feastlink', waitForConnections: true,
  connectionLimit: 10, queueLimit: 0, dateStrings: true
});
if (process.env.NODE_ENV !== 'production') globalForDb.mysqlPool = pool;

let mongoPromise: Promise<MongoClient> | null = null;
export async function mongoDb() {
  if (!process.env.MONGODB_URI) throw new Error('MONGODB_URI is not configured');
  if (!mongoPromise) {
    const client = globalForDb.mongoClient ?? new MongoClient(process.env.MONGODB_URI);
    if (!globalForDb.mongoClient) globalForDb.mongoClient = client;
    mongoPromise = client.connect();
  }
  const client = await mongoPromise;
  return client.db(process.env.MONGODB_DATABASE || 'feastlink_logs');
}
export async function audit(action: string, userId: number | null, details: Record<string, unknown> = {}) {
  try { const db = await mongoDb(); await db.collection('activity_logs').insertOne({ action, userId, details, createdAt: new Date() }); }
  catch (e) { console.warn('MongoDB audit log unavailable:', (e as Error).message); }
}
export async function notify(userId: number, title: string, message: string, type = 'info') {
  try { const db = await mongoDb(); await db.collection('notifications').insertOne({ userId, title, message, type, read: false, createdAt: new Date() }); }
  catch (e) { console.warn('MongoDB notification unavailable:', (e as Error).message); }
}
