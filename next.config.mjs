/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  poweredByHeader: false,
  // 기존 저장소 폴더(시안·문서·인프라)는 앱 빌드 대상이 아님
  outputFileTracingExcludes: { '*': ['mockup/**', 'docs/**', 'simulation/**', 'marketing/**', 'mailserver/**', 'infra/**'] },
};
export default nextConfig;
