module.exports = {
  "title": "Panko Serializers",
  "tagline": "High Performance JSON Serialization for ActiveRecord & Ruby Objects",
  "url": "https://panko.dev",
  "baseUrl": "/",
  "organizationName": "yosiat",
  "projectName": "panko_serializer",
  "favicon": "favicon.ico",
  "customFields": {
    "repoPath": "yosiat/panko_serializer",
    "repoUrl": "https://github.com/yosiat/panko_serializer",
  },
  "onBrokenLinks": "log",
  "onBrokenMarkdownLinks": "log",
  "presets": [
    [
      "@docusaurus/preset-classic",
      {
        "docs": {
          "path": "./docs",
          "showLastUpdateAuthor": false,
          "showLastUpdateTime": false,
          "sidebarPath": "./sidebars.json",
          "routeBasePath": "/"
        },
        "blog": false,
        "pages": false,
        "theme": {
          "customCss": "./src/css/customTheme.css"
        }
      }
    ]
  ],
  "plugins": [],
  "themeConfig": {
    "navbar": {
      "title": "Panko Serializers",
      "items": [
        {
          "to": "introduction",
          "label": "Docs",
          "position": "left"
        }
      ]
    },
    "image": "img/undraw_online.svg",
    "footer": {
      "links": [
        {
          title: "GitHub",
          items: [
            {
              label: "Repository",
              href: "https://github.com/yosiat/panko_serializer"
            },
            {
              label: "Discussions",
              href: "https://github.com/yosiat/panko_serializer/discussions"
            },
            {
              label: "Issues",
              href: "https://github.com/yosiat/panko_serializer/issues"
            },
            {
              "html": `
                  <iframe
                    src="https://ghbtns.com/github-btn.html?user=yosiat&amp;repo=panko_serializer&amp;type=star&amp;count=true&amp;size=medium"
                    title="GitHub Stars"
                  />`
            }
          ]
        }
      ],
      "copyright": `Copyright © ${new Date().getFullYear()} Panko Serializer`,
    },
    prism: {
      theme: require('prism-react-renderer/themes/github'), // Optional: Customize theme
      darkTheme: require('prism-react-renderer/themes/dracula'), // Optional: Dark theme
      additionalLanguages: ['ruby'], // Add Ruby as an additional language
    },
  }
}