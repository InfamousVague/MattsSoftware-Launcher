/// Vite config — mirrors the Libre.academy Tauri+Base wiring.
/// The two load-bearing bits: the `@base` alias points at the
/// symlinked node_modules path (created by the `file:../../Libs/base`
/// dependency), and `server.fs.allow` whitelists the linked Base
/// source so the dev server will serve its raw .tsx/.css through the
/// symlink instead of 403-ing out-of-root reads.
import { defineConfig } from "vite";
import { resolve } from "path";
import react from "@vitejs/plugin-react";

const host = process.env.TAURI_DEV_HOST;

export default defineConfig(async () => ({
  plugins: [react()],
  resolve: {
    alias: {
      "@base": resolve(__dirname, "node_modules/@mattmattmattmatt/base"),
    },
  },
  build: { outDir: "dist" },
  // Tauri expects a fixed dev port; surface Rust build output rather
  // than letting Vite wipe the terminal.
  clearScreen: false,
  server: {
    port: 1420,
    strictPort: true,
    host: host || false,
    fs: {
      allow: [resolve(__dirname), resolve(__dirname, "../../Libs/base")],
    },
    hmr: host ? { protocol: "ws", host, port: 1421 } : undefined,
    watch: { ignored: ["**/src-tauri/**"] },
  },
}));
