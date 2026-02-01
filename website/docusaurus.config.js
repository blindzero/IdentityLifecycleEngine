// @ts-check
// `@type` JSDoc annotations allow editor autocompletion and type checking
// (when paired with `@ts-check`).
// There are various equivalent ways to declare your Docusaurus config.
// See: https://docusaurus.io/docs/api/docusaurus-config

const { themes } = require('prism-react-renderer');
const lightCodeTheme = themes.github;
const darkCodeTheme = themes.dracula;

const repoOwner = 'blindzero';
const repoName = 'IdentityLifecycleEngine';

// This runs in Node.js - Don't use client-side code here (browser APIs, JSX...)

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: 'IdLE',
  tagline: 'Identity Lifecycle Engine',
  favicon: 'assets/logos/favicon.ico',

  // Future flags, see https://docusaurus.io/docs/api/docusaurus-config#future
  future: {
    v4: true, // Improve compatibility with the upcoming Docusaurus v4
  },

  // GitHub Pages Project site:
  url: `https://${repoOwner}.github.io`,
  baseUrl: `/${repoName}/`,

  // GitHub pages deployment config.
  // If you aren't using GitHub pages, you don't need these.
  organizationName: repoOwner, // Usually your GitHub org/user name.
  projectName: repoName, // Usually your repo name.

  onBrokenLinks: 'warn',
  
  // Even if you don't use internationalization, you can use this field to set
  // useful metadata like html lang. For example, if your site is Chinese, you
  // may want to replace "en" with "zh-Hans".
  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  presets: [
    [
      'classic',
      /** @type {import('@docusaurus/preset-classic').Options} */
      {
        docs: {
          // Use docs from repo root (/docs)
          path: '../docs',
          routeBasePath: 'docs', // docs at /docs/...
          sidebarPath: require.resolve('./sidebars.js'),

          // Edit links point to repo root, not /website
          editUrl: `https://github.com/${repoOwner}/${repoName}/edit/main/`,
          exclude: [
            '**/develop/**',
            '_*template.md',
            '**/index.md',
            'index.md'], 
        },
        
        blog: false, // Disable blog plugin - maybe enable later
        
        theme: {
          customCss: require.resolve('./src/css/custom.css'),
        },

        sitemap: {
          changefreq: 'weekly',
          priority: 0.5,
        },
      },
    ],
  ],

  themeConfig:
    /** @type {import('@docusaurus/preset-classic').ThemeConfig} */
    ({
      // Replace with your project's social card
      image: 'img/idle-social-card.jpg',
      navbar: {
        title: 'IdLE',
        logo: {
          alt: 'IdLE - Identity Lifecycle Engine',
          src: 'assets/logos/idle_logo_flat_white.png',
        },
        items: [
          { to: '/docs/about/intro', label: 'About IdLE', position: 'left'},
          { to: '/docs/use/intro', label: 'Use IdLE', position: 'left'},
          { to: '/docs/extend/intro', label: 'Extend IdLE', position: 'left'},
          { to: '/docs/reference/intro', label: 'Reference', position: 'left'},
          {
            href: `https://github.com/${repoOwner}/${repoName}`,
            label: 'GitHub',
            position: 'right',
          },
        ],
      },

      footer: {
        style: 'dark',
        /*
        links: [
          {
            title: 'Docs',
            items: [
              { label: 'User Guide', to: '/docs/user/intro' },
              { label: 'Developer Guide', to: '/docs/developer/intro' },
            ],
          },
          {
            title: 'Project',
            items: [
              { label: 'GitHub', href: `https://github.com/${repoOwner}/${repoName}` },
              { label: 'Releases', href: `https://github.com/${repoOwner}/${repoName}/releases` },
            ],
          },
        ],
        */
        copyright: `Copyright © ${new Date().getFullYear()} IdLE Project, Built with Docusaurus.`,
      },

      prism: {
        theme: lightCodeTheme,
        darkTheme: darkCodeTheme,
        additionalLanguages: ['powershell', 'json', 'yaml', 'bash'],
      },

      // Optional: dark mode on/off (default: on, can be adjusted)
      colorMode: {
        defaultMode: 'light',
        disableSwitch: false,
        respectPrefersColorScheme: true,
      },

      zoom: {
        // for docusaurus-plugin-image-zoom
        selector: '.markdown :not(em) > img',
        background: {
          light: 'rgb(255, 255, 255)',
          dark: 'rgb(24, 25, 26)',
        },
      },
    }),
  
  plugins: [
    // Local search (no Algolia account needed)
    [
      require.resolve('@easyops-cn/docusaurus-search-local'),
      {
        indexDocs: true,
        indexPages: true,
        indexBlog: false,
        docsRouteBasePath: '/docs',
      },
    ],

    // Redirects (helpful when docs move later)
    [
      require.resolve('@docusaurus/plugin-client-redirects'),
      {
        redirects: [
          // Example:
          { from: ['/docs'], to: '/docs/about/intro' },
        ],
      },
    ],

    // Image zoom
    require.resolve('docusaurus-plugin-image-zoom'),
  ],

  themes: [
    // GitHub-like codeblock styling (similar vibe to IOTA)
    require.resolve('@saucelabs/theme-github-codeblock'),

    // Optional Mermaid support (if installed)
    require.resolve('@docusaurus/theme-mermaid'),
  ],

  // If you enable Mermaid theme above, also enable markdown mermaid:
  // markdown: { mermaid: true },
  markdown: {
    hooks: {
      onBrokenMarkdownLinks: 'warn',
      onBrokenMarkdownImages: 'warn',
    }
  },
};

module.exports = config;
