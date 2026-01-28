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
      ],
    },
    {
      type: 'category',
      label: 'Use IdLE',
      collapsed: false,
      items: [
        'use/intro',
      ],
    },
    {
      type: 'category',
      label: 'Extend IdLE',
      collapsed: false,
      items: [
        'extend/intro',
      ],
    },
    {
      type: 'category',
      label: 'Reference',
      collapsed: true,
      items: [
        'reference/intro',
      ],
    },
  ],
};

export default sidebars;
