import type { Metadata, Viewport } from 'next';
import './globals.css';

export const metadata: Metadata = { title: '소개뱅크', description: '좋은 상품을 소개하고 함께 성장하는 소개뱅크' };
export const viewport: Viewport = { width: 'device-width', initialScale: 1, viewportFit: 'cover', themeColor: '#2457D6' };

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="ko">
      <body>{children}</body>
    </html>
  );
}
