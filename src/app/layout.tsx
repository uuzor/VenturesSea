import type { Metadata } from "next";
import "@/styles/globals.css";
import { Providers } from "./providers";
import { NavBar, Footer } from "@/components/layout";

export const metadata: Metadata = {
  title: "VenturesSea — IdeaFi Protocol",
  description: "Community-driven funding, governance, and P2P token trading for the next generation of builders.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body className="font-inter antialiased">
        <Providers>
          <NavBar />
          {children}
          <Footer />
        </Providers>
      </body>
    </html>
  );
}
