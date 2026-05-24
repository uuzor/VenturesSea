import Link from 'next/link';

export default function HomePage() {
  return (
    <div className="min-h-screen pt-16 bg-[var(--color-warm-canvas)]">
      {/* Hero Section */}
      <section className="relative min-h-[80vh] flex items-center justify-center px-8 py-20">
        <div className="max-w-[1200px] mx-auto text-center">
          <span className="inline-block px-4 py-1.5 bg-[var(--color-stone-surface)] rounded-full text-sm font-medium text-[var(--color-ember-orange)] mb-6">
            Hackathon-style Builder Selection
          </span>
          <h1 className="font-family text-5xl md:text-6xl lg:text-[68px] font-medium leading-[1.09] tracking-[-2.11px] text-[var(--color-charcoal-primary)] mb-6">
            Where Great Ideas<br />
            <span className="text-[var(--color-ember-orange)]">Meet Builders</span>
          </h1>
          <p className="max-w-2xl mx-auto text-lg md:text-xl text-[var(--color-graphite)] leading-relaxed mb-10">
            VenturesSea connects visionary founders with talented builders through 
            community-driven funding and transparent governance.
          </p>
          <div className="flex flex-col sm:flex-row items-center justify-center gap-4">
            <Link href="/ideas">
              <button className="px-8 py-4 bg-[var(--color-midnight)] text-white rounded-[32px] font-inter font-medium text-sm hover:bg-[var(--color-charcoal-primary)] transition-all">
                Explore Ideas
              </button>
            </Link>
            <Link href="/apply">
              <button className="px-8 py-4 bg-[var(--color-stone-surface)] text-[var(--color-midnight)] rounded-[32px] font-inter font-medium text-sm hover:bg-[var(--color-parchment-card)] transition-all">
                Apply as Builder
              </button>
            </Link>
          </div>
          <div className="mt-16 grid grid-cols-3 gap-8 max-w-xl mx-auto">
            <div className="text-center">
              <div className="text-2xl md:text-3xl font-semibold text-[var(--color-charcoal-primary)]">$2.4M+</div>
              <div className="text-sm text-[var(--color-ash)] mt-1">Total Funded</div>
            </div>
            <div className="text-center">
              <div className="text-2xl md:text-3xl font-semibold text-[var(--color-charcoal-primary)]">48</div>
              <div className="text-sm text-[var(--color-ash)] mt-1">Ideas Launched</div>
            </div>
            <div className="text-center">
              <div className="text-2xl md:text-3xl font-semibold text-[var(--color-charcoal-primary)]">156</div>
              <div className="text-sm text-[var(--color-ash)] mt-1">Builders Connected</div>
            </div>
          </div>
        </div>
      </section>

      {/* How It Works */}
      <section className="py-[140px] bg-[var(--color-parchment-card)]">
        <div className="max-w-[1200px] mx-auto px-8">
          <div className="text-center mb-16">
            <span className="inline-block px-4 py-1.5 bg-[var(--color-stone-surface)] rounded-full text-sm font-medium text-[var(--color-sky-blue)] mb-4">
              How It Works
            </span>
            <h2 className="font-family text-4xl md:text-[44px] font-medium leading-[1.09] tracking-[-1.14px] text-[var(--color-midnight)]">
              From Idea to Reality
            </h2>
          </div>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
            {[
              { num: '01', title: 'Submit Your Idea', desc: 'Founders submit project proposals with clear scope and budget.' },
              { num: '02', title: 'Builder Applications', desc: 'Builders apply off-chain with portfolios and proposed timelines.' },
              { num: '03', title: 'Hackathon Selection', desc: 'Community votes to shortlist builders who build prototypes.' },
              { num: '04', title: 'Winner & On-Chain', desc: 'Winner selected, contracts deploy, development begins.' },
            ].map((step, i) => (
              <div key={i} className="relative p-6 bg-white rounded-[10px] shadow-[inset_0_0_0_1px_rgba(242,240,237,0.9)]">
                <div className="absolute -top-4 -left-4 w-10 h-10 bg-[var(--color-ember-orange)] rounded-full flex items-center justify-center text-white font-bold text-lg">
                  {step.num}
                </div>
                <h3 className="text-lg font-semibold text-[var(--color-charcoal-primary)] mb-2 mt-4">
                  {step.title}
                </h3>
                <p className="text-sm text-[var(--color-graphite)] leading-relaxed">
                  {step.desc}
                </p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Features */}
      <section className="py-[140px]">
        <div className="max-w-[1200px] mx-auto px-8">
          <div className="text-center mb-16">
            <span className="inline-block px-4 py-1.5 bg-[var(--color-stone-surface)] rounded-full text-sm font-medium text-[var(--color-meadow-green)] mb-4">
              Platform Features
            </span>
            <h2 className="font-family text-4xl md:text-[44px] font-medium leading-[1.09] tracking-[-1.14px] text-[var(--color-midnight)]">
              Built for Creators
            </h2>
          </div>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {[
              { title: 'Community-Driven Selection', desc: 'Token holders vote on builder applications.' },
              { title: 'Milestone-Based Funding', desc: 'Funds release as builders hit milestones.' },
              { title: 'Fair Compensation', desc: 'All builders receive compensation for participation.' },
              { title: 'Secondary Market Trading', desc: 'Idea tokens tradeable on secondary market.' },
              { title: 'Decentralized Governance', desc: 'IdeaDAO manages projects through voting.' },
              { title: 'Revenue Sharing', desc: 'Investors receive share of project revenue.' },
            ].map((feature, i) => (
              <div key={i} className="group p-8 bg-white rounded-[10px] shadow-[inset_0_0_0_1px_rgba(242,240,237,0.9)] hover:shadow-[var(--shadow-sm)] hover:-translate-y-1 transition-all duration-300">
                <h3 className="text-[19px] font-semibold text-[var(--color-charcoal-primary)] mb-3">
                  {feature.title}
                </h3>
                <p className="text-[var(--color-graphite)] leading-relaxed">
                  {feature.desc}
                </p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* CTA */}
      <section className="py-[140px] bg-[var(--color-midnight)]">
        <div className="max-w-[1200px] mx-auto px-8 text-center">
          <h2 className="font-family text-4xl md:text-[44px] font-medium leading-[1.09] tracking-[-1.14px] text-white mb-6">
            Ready to Launch Your Idea?
          </h2>
          <p className="max-w-xl mx-auto text-lg text-[var(--color-fog)] mb-10">
            Join the community of founders and builders creating the next generation of decentralized applications.
          </p>
          <div className="flex flex-col sm:flex-row items-center justify-center gap-4">
            <Link href="/ideas">
              <button className="px-8 py-4 bg-[var(--color-ember-orange)] text-white rounded-[32px] font-inter font-medium text-sm hover:opacity-90 transition-all">
                Submit Your Idea
              </button>
            </Link>
            <Link href="/apply">
              <button className="px-8 py-4 bg-[var(--color-stone-surface)] text-[var(--color-midnight)] rounded-[32px] font-inter font-medium text-sm hover:bg-[var(--color-parchment-card)] transition-all">
                Apply as Builder
              </button>
            </Link>
          </div>
        </div>
      </section>
    </div>
  );
}
