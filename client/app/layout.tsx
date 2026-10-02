import type { Metadata } from "next";
import type { ReactNode } from "react";
import "./styles.css";

export const metadata: Metadata = {
  title: "Авто лаборатория",
  description: "Заявки на технический осмотр и аналитика просмотров",
};

export default function RootLayout({ children }: Readonly<{ children: ReactNode }>) {
  return (
    <html lang="ru" translate="no">
      <body>{children}</body>
    </html>
  );
}
