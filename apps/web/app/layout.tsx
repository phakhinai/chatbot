import type { ReactNode } from 'react';
import './globals.css';
export const metadata = { title: 'RAG Chatbot — Development', description: 'Local development environment' };
export default function Layout({ children }: { children: ReactNode }) {
  return <html lang="th"><body>{children}</body></html>;
}
