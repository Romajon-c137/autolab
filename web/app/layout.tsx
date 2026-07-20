import "./styles.css";
import type { ReactNode } from "react";

export const metadata = {
  title: "Авто лаборатория",
  description: "Реестр осмотров и отчеты",
};

export default function RootLayout({
  children,
}: Readonly<{ children: ReactNode }>) {
  return (
    <html lang="ru" translate="no">
      <body>{children}</body>
    </html>
  );
}
