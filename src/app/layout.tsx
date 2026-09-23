import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "営業日報システム",
  description: "営業担当者の日々の訪問記録と上長のフィードバックを管理する",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="ja">
      <body>{children}</body>
    </html>
  );
}
