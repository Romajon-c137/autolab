import type { Metadata } from "next";
import type { ReactNode } from "react";
import "./styles.css";

export const metadata: Metadata = {
  title: "Авто лаборатория - заявка",
  description: "Клиентская заявка на проведение технического осмотра",
};

export default function RootLayout({ children }: Readonly<{ children: ReactNode }>) {
  return (
    <html lang="ru" translate="no">
      <body>{children}</body>
    </html>
  );
}
