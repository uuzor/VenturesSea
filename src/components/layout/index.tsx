'use client';

import React from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import ConnectButton from '@/components/wallet/ConnectButton';
import { useAccount } from 'wagmi';

interface LogoProps {
  size?: 'sm' | 'md' | 'lg';
}

const Logo: React.FC<LogoProps> = ({ size = 'md' }) => {
  const sizeStyles = {
    sm: 'text-lg gap-2',
    md: 'text-xl gap-3',
    lg: 'text-2xl gap-4',
  };

  return (
    <Link href="/" className={`flex items-center font-family font-medium ${sizeStyles[size]} text-[var(--color-charcoal-primary)] no-underline`}>
      <svg width="32" height="32" viewBox="0 0 32 32" fill="none" className="flex-shrink-0">
        <rect width="32" height="32" rx="8" fill="var(--color-ember-orange)" />
        <path d="M8 22L16 10L24 22M11 18H21" stroke="white" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" />
      </svg>
      <span className="hidden sm:block">VenturesSea</span>
    </Link>
  );
};

const NavLink: React.FC<{ href: string; children: React.ReactNode; isActive?: boolean }> = ({ href, children, isActive }) => (
  <Link
    href={href}
    className={`
      relative px-4 py-2 rounded-full
      font-inter font-medium text-sm
      transition-all duration-200
      ${isActive ? 'bg-[var(--color-midnight)] text-white' : 'text-[var(--color-charcoal-primary)] hover:bg-[var(--color-stone-surface)]'}
    `}
  >
    {children}
  </Link>
);

const NavBar: React.FC = () => {
  const pathname = usePathname();
  const { address, isConnected } = useAccount();

  const navLinks = [
    { href: '/ideas', label: 'Explore' },
    { href: '/market', label: 'Market' },
    { href: '/submit', label: 'Submit' },
    { href: '/vote', label: 'Vote' },
    { href: '/dashboard', label: 'Dashboard' },
  ];

  const formatAddress = (addr: string) => `${addr.slice(0, 6)}...${addr.slice(-4)}`;

  return (
    <nav className="fixed top-0 left-0 right-0 z-50 h-20 bg-white/80 backdrop-blur-lg border-b border-[var(--color-stone-surface)]/50">
      <div className="max-w-[1400px] mx-auto px-8 h-full flex items-center justify-between">
        <div className="flex items-center gap-8">
          <Logo size="md" />
          <div className="hidden md:flex items-center gap-2">
            {navLinks.map((link) => (
              <NavLink key={link.href} href={link.href} isActive={pathname === link.href}>
                {link.label}
              </NavLink>
            ))}
          </div>
        </div>

        <div className="flex items-center gap-4">
          {isConnected ? (
            <div className="hidden sm:flex items-center gap-2 px-4 py-2 bg-[var(--color-stone-surface)] rounded-full">
              <div className="w-2 h-2 bg-[var(--color-meadow-green)] rounded-full animate-pulse" />
              <span className="text-sm font-medium text-[var(--color-charcoal-primary)]">
                {formatAddress(address || '')}
              </span>
            </div>
          ) : null}
          <ConnectButton />
        </div>
      </div>
    </nav>
  );
};

const Footer: React.FC = () => {
  const footerLinks = {
    Product: [
      { label: 'Explore Ideas', href: '/ideas' },
      { label: 'Token Market', href: '/market' },
      { label: 'Submit Idea', href: '/submit' },
    ],
    Community: [
      { label: 'Vote', href: '/vote' },
      { label: 'Dashboard', href: '/dashboard' },
      { label: 'Admin', href: '/admin' },
    ],
    Resources: [
      { label: 'Documentation', href: '/docs' },
      { label: 'Contracts', href: '/contracts' },
      { label: 'Contact', href: '/contact' },
    ],
  };

  return (
    <footer className="bg-[var(--color-midnight)] text-white">
      <div className="max-w-[1400px] mx-auto px-8 py-20">
        <div className="grid grid-cols-1 md:grid-cols-4 gap-12 mb-16">
          <div className="md:col-span-1">
            <Logo size="lg" />
            <p className="mt-6 text-[var(--color-fog)] leading-relaxed max-w-sm">
              Empowering innovation through community-driven funding, governance, and P2P token trading.
            </p>
            <div className="flex items-center gap-3 mt-6">
              <a href="#" className="w-10 h-10 bg-white/10 rounded-full flex items-center justify-center hover:bg-[var(--color-ember-orange)] transition-colors">
                <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 24 24"><path d="M23.953 4.57a10 10 0 01-2.825.775 4.958 4.958 0 002.163-2.723c-.951.555-2.005.959-3.127 1.184a4.92 4.92 0 00-8.384 4.482C7.69 8.095 4.067 6.13 1.64 3.162a4.822 4.822 0 00-.666 2.475c0 1.71.87 3.213 2.188 4.096a4.904 4.904 0 01-2.228-.616v.06a4.923 4.923 0 003.946 4.827 4.996 4.996 0 01-2.212.085 4.936 4.936 0 004.604 3.417 9.867 9.867 0 01-6.102 2.105c-.39 0-.779-.023-1.17-.067a13.995 13.995 0 007.557 2.209c9.053 0 13.998-7.496 13.998-13.985 0-.21 0-.42-.015-.63A9.935 9.935 0 0024 4.59z" /></svg>
              </a>
              <a href="#" className="w-10 h-10 bg-white/10 rounded-full flex items-center justify-center hover:bg-[var(--color-ember-orange)] transition-colors">
                <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 24 24"><path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z" /></svg>
              </a>
              <a href="#" className="w-10 h-10 bg-white/10 rounded-full flex items-center justify-center hover:bg-[var(--color-ember-orange)] transition-colors">
                <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 24 24"><path d="M20.317 4.3698a19.7913 19.7913 0 00-4.8851-1.5152.0741.0741 0 00-.0785.0371c-.211.3753-.4447.8648-.6083 1.2495-1.8447-.2762-3.68-.2762-5.4868 0-.1636-.3933-.4058-.8742-.6177-1.2495a.077.077 0 00-.0785-.037 19.7363 19.7363 0 00-4.8852 1.515.0699.0699 0 00-.0321.0277C.5334 9.0458-.319 13.5799.0992 18.0578a.0824.0824 0 00.0312.0561c2.0528 1.5076 4.0413 2.4228 5.9929 3.0294a.0777.0777 0 00.0842-.0276c.4616-.6304.8731-1.2952 1.226-1.9942a.076.076 0 00-.0416-.1057c-.6528-.2476-1.2743-.5495-1.8722-.8923a.077.077 0 01-.0076-.1277c.1258-.0943.2517-.1923.3718-.2914a.0743.0743 0 01.0776-.0105c3.9278 1.7933 8.18 1.7933 12.0614 0a.0739.0739 0 01.0785.0095c.1202.0988.2458.1968.3728.2924a.077.077 0 01-.0066.1276 12.2986 12.2986 0 01-1.873.8914.0766.0766 0 00-.0407.1067c.3604.698.7719 1.3628 1.225 1.9932a.076.076 0 00.0842.0286c1.961-.6067 3.9495-1.5219 6.0023-3.0294a.077.077 0 00.0313-.0552c.5004-5.177-.8382-9.6739-3.5485-13.6604a.061.061 0 00-.0312-.0286zM8.02 15.3312c-1.1825 0-2.1569-1.0857-2.1569-2.419 0-1.3332.9555-2.4189 2.157-2.4189 1.2108 0 2.1757 1.0952 2.1568 2.419 0 1.3332-.9555 2.4189-2.1569 2.4189zm7.9748 0c-1.1825 0-2.1569-1.0857-2.1569-2.419 0-1.3332.9554-2.4189 2.1569-2.4189 1.2108 0 2.1757 1.0952 2.1568 2.419 0 1.3332-.946 2.4189-2.1568 2.4189Z" /></svg>
              </a>
            </div>
          </div>
          {Object.entries(footerLinks).map(([title, links]) => (
            <div key={title}>
              <h3 className="font-semibold text-sm uppercase tracking-wider mb-6">{title}</h3>
              <ul className="space-y-4">
                {links.map((link) => (
                  <li key={link.href}>
                    <Link href={link.href} className="text-[var(--color-fog)] hover:text-[var(--color-ember-orange)] transition-colors">
                      {link.label}
                    </Link>
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>
        <div className="pt-8 border-t border-white/10 flex flex-col md:flex-row justify-between items-center gap-4">
          <p className="text-sm text-[var(--color-fog)]">© {new Date().getFullYear()} VenturesSea. All rights reserved.</p>
          <div className="flex items-center gap-6 text-sm text-[var(--color-fog)]">
            <a href="#" className="hover:text-white transition-colors">Privacy</a>
            <a href="#" className="hover:text-white transition-colors">Terms</a>
          </div>
        </div>
      </div>
    </footer>
  );
};

export { Logo, NavBar, Footer };
