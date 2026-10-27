export const dynamic = 'force-dynamic';
export default async function Home() {
  let ready = false;
  try {
    const response = await fetch(`${process.env.API_INTERNAL_URL || 'http://127.0.0.1:3001'}/health`, { cache: 'no-store', signal: AbortSignal.timeout(4000) });
    ready = response.ok && (await response.json()).status === 'ok';
  } catch { /* Render a useful page even while the backend is starting. */ }
  return <main><p>LOCAL DEVELOPMENT</p><h1>AI RAG Chatbot</h1><h2>{ready ? 'ระบบพื้นฐานพร้อมใช้งาน' : 'กำลังรอ Backend หรือบริการฐานข้อมูล'}</h2><p>Next.js · NestJS · PostgreSQL + pgvector · Redis</p><p>Backend และฐานข้อมูล: <strong>{ready ? 'Connected' : 'Unavailable'}</strong></p><p>สภาพแวดล้อมสำหรับพัฒนา — ยังไม่ได้เปิดใช้ฟีเจอร์แชตและ RAG</p></main>;
}
