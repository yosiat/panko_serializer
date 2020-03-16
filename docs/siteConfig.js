/**
 * Copyright (c) 2017-present, Facebook, Inc.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// See https://docusaurus.io/docs/site-config for all the possible
// site configuration options.


// List of projects/orgs using your project for the users page.
const users = [
  {
    caption: 'User1',
    // You will need to prepend the image path with your baseUrl
    // if it is not '/', like: '/test-site/img/image.jpg'.
    image: '/img/undraw_open_source.svg',
    infoLink: 'https://www.facebook.com',
    pinned: true,
  },
];

const siteConfig = {
  title: 'Panko Serializers',
  tagline: 'High Performance JSON Serialization for ActiveRecord & Ruby Objects',
  url: 'https://panko.dev',
  baseUrl: '/',
  repoPath: 'panko-serializer/panko_serializer',
  // For github.io type URLs, you would set the url and baseUrl like:
  //   url: 'https://facebook.github.io',
  //   baseUrl: '/test-site/',
  customDocsPath: require('path').basename(__dirname) + '/docs',

  repoUrl: 'https://github.com/panko-serializer/panko_serializer',
  projectName: 'panko_serializer',
  organizationName: 'panko-serializer',
  cname: 'panko.dev',

  headerLinks: [
    {doc: 'index', label: 'Docs'},
  ],

  /* Colors for website */
  colors: {
    //primaryColor: '#3F4C6B',
    primaryColor: '#B02B2C',
    secondaryColor: '#C3D9FF',
  },

  copyright: `Copyright © ${new Date().getFullYear()} Panko Serializer`,

  usePrims: ['ruby'],
  highlight: {
    // Highlight.js theme to use for syntax highlighting in code blocks.
    theme: 'atom-one-dark',
  },

  // Add custom scripts here that would be placed in <script> tags.
  scripts: ['https://buttons.github.io/buttons.js'],

  // On page navigation for the current documentation page.
  onPageNav: 'separate',
  // No .html extensions for paths.
  cleanUrl: true,

  // Open Graph and Twitter card images.
  ogImage: 'img/undraw_online.svg',
  twitterImage: 'img/undraw_tweetstorm.svg',

  // Show documentation's last contributor's name.
  // enableUpdateBy: true,

  // Show documentation's last update time.
  // enableUpdateTime: true,

  // You may provide arbitrary config keys to be used as needed by your
};

module.exports = siteConfig;
