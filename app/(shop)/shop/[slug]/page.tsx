export default async function Page({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  return (
    <main className="wrap">
      <div className="brand">소개뱅크 <span>개인몰</span></div>
      <section className="card" style={{ marginTop: 16 }}>
        <p className="muted">{slug}.sogaebank.com 개인몰 (TEN-1에서 하위 주소로 연결, S8 SHOP-1에서 구현)</p>
      </section>
    </main>
  );
}
