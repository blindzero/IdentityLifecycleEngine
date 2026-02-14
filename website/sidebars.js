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
        'about/security',
      ],
    },
    {
      type: 'category',
      label: 'Use IdLE',
      collapsed: false,
      items: [
        'use/intro-use',
        'use/installation',
        'use/quickstart',
        'use/workflows',
        'use/providers',
        'use/plan-export',
      ],
    },
    {
      type: 'category',
      label: 'Extend IdLE',
      collapsed: false,
      items: [
        'extend/intro-extend',
        'extend/extensibility',
        // Add later if/when you create them:
        // 'extend/providers',
        // 'extend/steps',
        // 'extend/events',
        // 'extend/auth-sessions',
        // 'extend/testing',
      ],
    },
    {
      type: 'category',
      label: 'Reference',
      collapsed: true,
      items: [
        'reference/intro-reference',
        'reference/cmdlets',
        {
          type: 'category',
          label: 'Cmdlet Reference',
          collapsed: true,
          items: [
            'reference/cmdlets/Export-IdlePlan',
            'reference/cmdlets/Invoke-IdlePlan',
            'reference/cmdlets/New-IdleAuthSession',
            'reference/cmdlets/New-IdleRequest',
            'reference/cmdlets/New-IdlePlan',
            'reference/cmdlets/Test-IdleWorkflow',
          ],
        },
        'reference/steps',
        {
          type: 'category',
          label: 'Step Reference',
          collapsed: true,
          items: [
            'reference/steps/step-create-identity',
            'reference/steps/step-delete-identity',
            'reference/steps/step-disable-identity',
            'reference/steps/step-revoke-identity-sessions',
            'reference/steps/step-enable-identity',
            'reference/steps/step-emit-event',
            'reference/steps/step-ensure-attributes',
            'reference/steps/step-ensure-entitlement',
            'reference/steps/step-move-identity',
            'reference/steps/step-trigger-directory-sync',
            'reference/steps/step-mailbox-get-info',
            'reference/steps/step-mailbox-ensure-type',
            'reference/steps/step-mailbox-ensure-out-of-office',
          ]
        },
        'reference/providers',
        {
          type: 'category',
          label: 'Provider Reference',
          collapsed: true,
          items: [
            'reference/providers/provider-ad',
            'reference/providers/provider-entraID',
            'reference/providers/provider-directorysync-entraconnect',
            'reference/providers/provider-exchangeonline',
            'reference/providers/provider-mock',
          ],
        },
        'reference/capabilities',
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
