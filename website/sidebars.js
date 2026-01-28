// @ts-check

// This runs in Node.js - Don't use client-side code here (browser APIs, JSX...)

/**
 * Creating a sidebar enables you to:
 - create an ordered group of docs
 - render a sidebar for each doc of that group
 - provide next/previous navigation

 The sidebars can be generated from the filesystem, or explicitly defined here.

 Create as many sidebars as you want.

 @type {import('@docusaurus/plugin-content-docs').SidebarsConfig}
 */
const sidebars = {
  docs: [
    {
      type: 'category',
      label: 'About',
      collapsed: false,
      items: [
        'about/intro',
        'about/concepts',
        'about/architecture',
        'about/security',
      ],
    },
    {
      type: 'category',
      label: 'Use IdLE',
      collapsed: false,
      items: [
        'use/intro',
        'use/installation',
        'use/quickstart',
        'use/workflows',
        'use/providers',
        'use/steps',
        'use/configuration',
        'use/plan-export',
      ],
    },
    {
      type: 'category',
      label: 'Extend IdLE',
      collapsed: false,
      items: [
        'extend/intro',
        'extend/extensibility',
        'extend/providers',
        'extend/steps',
        'extend/events',
        // Add later if/when you create them:
        // 'extend/auth-sessions',
        // 'extend/testing',
      ],
    },
    {
      type: 'category',
      label: 'Reference',
      collapsed: true,
      items: [
        'reference/intro',
        'reference/capabilities',
        'reference/steps',
        'reference/cmdlets',
        {
          type: 'category',
          label: 'Cmdlets',
          collapsed: true,
          items: [
            'reference/cmdlets/Export-IdlePlan',
            'reference/cmdlets/Invoke-IdlePlan',
            'reference/cmdlets/New-IdleAuthSession',
            'reference/cmdlets/New-IdleLifecycleRequest',
            'reference/cmdlets/New-IdlePlan',
            'reference/cmdlets/Test-IdleWorkflow',
          ],
        },
        {
          type: 'category',
          label: 'Providers',
          collapsed: true,
          items: [
            'reference/providers/provider-ad',
            'reference/providers/provider-entraID',
          ],
        },
        {
          type: 'category',
          label: 'Specs',
          collapsed: true,
          items: [
            'reference/specs/plan-export',
          ],
        },
      ],
    },
  ],
};

export default sidebars;
