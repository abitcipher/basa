import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import type { Plugin } from "vite";

const noSvarFonts = (): Plugin => ({
  name: "basa-no-svar-fonts",
  enforce: "pre",
  transform(code, id) {
    if (/@svar-ui\/.*\.css$/.test(id)) return code.replace(/@font-face\s*\{[^}]*\}/g, "");
  },
});

const chunkCss = (base: string): Plugin => ({
  name: "basa-chunk-css",
  enforce: "post",
  generateBundle(_options, bundle) {
    for (const chunk of Object.values(bundle)) {
      if (chunk.type !== "chunk") continue;
      const css = [...((chunk as any).viteMetadata?.importedCss ?? [])] as string[];
      if (css.length === 0) continue;
      const hrefs = JSON.stringify(css.map((file) => base + file));
      chunk.code =
        `for(const h of ${hrefs}){if(!document.querySelector('link[href="'+h+'"]')){const l=document.createElement("link");l.rel="stylesheet";l.href=h;document.head.appendChild(l)}}\n` +
        chunk.code;
    }
  },
});

export default defineConfig(({ mode }) => ({
  plugins: [noSvarFonts(), react(), chunkCss("/assets/widgets/")],
  base: "/assets/widgets/",
  define: { "process.env.NODE_ENV": JSON.stringify(mode === "development" ? "development" : "production") },
  build: {
    outDir: "../../priv/static/assets/widgets",
    emptyOutDir: true,
    sourcemap: mode === "development",
    cssCodeSplit: true,
    lib: {
      entry: { widgets: "src/main.tsx", sortable: "src/sortable.ts", devicekeys: "src/devicekeys.ts" },
      formats: ["es"],
      fileName: (_format, name) => `${name}.js`,
    },
    rollupOptions: { output: { chunkFileNames: "[name]-[hash].js", assetFileNames: "[name][extname]" } },
  },
}));
