import { QuartzConfig } from "./quartz/cfg"
import * as Plugin from "./quartz/plugins"

/**
 * claude-flight docs site.
 *
 * This file is overlaid onto an upstream Quartz v4 checkout by
 * .github/workflows/deploy-wiki.yml -- see wiki/README.md.
 */
const config: QuartzConfig = {
  configuration: {
    pageTitle: "claude-flight",
    pageTitleSuffix: "",
    enableSPA: true,
    enablePopovers: true,
    analytics: null,
    locale: "en-US",
    baseUrl: "wombat164.github.io/claude-flight",
    ignorePatterns: ["private", ".obsidian", "templates"],
    defaultDateType: "modified",
    theme: {
      fontOrigin: "googleFonts",
      cdnCaching: true,
      typography: {
        header: "Schibsted Grotesk",
        body: "Source Sans Pro",
        code: "IBM Plex Mono",
      },
      // "night cockpit" -- see assets/BRAND.md. #00E5A0 is the signature colour
      // (the horizon line); amber is reserved for caution, never decoration.
      colors: {
        lightMode: {
          light: "#F4F3F1",
          lightgray: "#E2E0DC",
          gray: "#9AA3AD",
          darkgray: "#3A424C",
          dark: "#0A0E14",
          secondary: "#00785A",
          tertiary: "#B87A00",
          highlight: "rgba(0, 120, 90, 0.10)",
          textHighlight: "#FFB00044",
        },
        darkMode: {
          light: "#0A0E14",
          lightgray: "#1E2733",
          gray: "#4A5766",
          darkgray: "#C9CCD1",
          dark: "#E8E6E3",
          secondary: "#00E5A0",
          tertiary: "#FFB000",
          highlight: "rgba(0, 229, 160, 0.10)",
          textHighlight: "#FFB00055",
        },
      },
    },
  },
  plugins: {
    transformers: [
      Plugin.FrontMatter(),
      Plugin.CreatedModifiedDate({ priority: ["frontmatter", "git", "filesystem"] }),
      Plugin.SyntaxHighlighting({ theme: { light: "github-light", dark: "github-dark" }, keepBackground: false }),
      Plugin.ObsidianFlavoredMarkdown({ enableInHtmlEmbed: false }),
      Plugin.GitHubFlavoredMarkdown(),
      Plugin.TableOfContents(),
      Plugin.CrawlLinks({ markdownLinkResolution: "shortest" }),
      Plugin.Description(),
    ],
    filters: [Plugin.RemoveDrafts()],
    emitters: [
      Plugin.AliasRedirects(),
      Plugin.ComponentResources(),
      Plugin.ContentPage(),
      Plugin.FolderPage(),
      Plugin.TagPage(),
      Plugin.ContentIndex({ enableSiteMap: true, enableRSS: true }),
      Plugin.Assets(),
      Plugin.Static(),
      Plugin.Favicon(),
      Plugin.NotFoundPage(),
      Plugin.CustomOgImages(),
    ],
  },
}

export default config
