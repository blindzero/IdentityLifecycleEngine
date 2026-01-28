import clsx from 'clsx';
import Link from '@docusaurus/Link';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import Layout from '@theme/Layout';
import HomepageFeatures from '@site/src/components/HomepageFeatures';

import Heading from '@theme/Heading';
import styles from './index.module.css';
import useBaseUrl from '@docusaurus/useBaseUrl';

function HomepageHeader() {
  const {siteConfig} = useDocusaurusContext();
  const heroLogoUrl = useBaseUrl('assets/logos/idle_logo_transparent.png');

  return (
    <header className={clsx('hero hero--primary', styles.heroBanner)}>
      <div className="container">

        {/* Row: Logo + Title/Subtitle */}
        <div className={styles.heroTopRow}>
          <img
            className={styles.heroLogo}
            src={heroLogoUrl}
            alt="IdLE logo"
            loading="eager"
          />

          <div className={styles.heroTitleBlock}>
            <Heading as="h1" className={clsx('hero__title', styles.heroTitle)}>
              {siteConfig.title}
            </Heading>
            <p className={clsx('hero__subtitle', styles.heroSubtitle)}>
              {siteConfig.tagline}
            </p>
          </div>
        </div>
        {/* Below: Text + CTA */}
        <div className={styles.heroBottom}>
          <p className={styles.heroLead}>
            IdLE is a <b>generic, headless, configuration-driven lifecycle orchestration engine</b><br/>for
            identity and account processes (Joiner / Mover / Leaver), built for PowerShell 7+.
          </p>

          <div className={styles.buttons}>
            <Link className="button button--secondary button--lg" to="/docs/use/quickstart">
              Get Started with IdLE in 5 Min ⏱️
            </Link>
          </div>
        </div>

      </div>
    </header>
  );
}

export default function Home() {
  const {siteConfig} = useDocusaurusContext();
  return (
    <Layout
      title={`Hello from ${siteConfig.title}`}
      description="Description will go into a meta tag in <head />">
      <HomepageHeader />
      <main>
        <HomepageFeatures />
      </main>
    </Layout>
  );
}
