import path from "node:path";
import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

// The page always comes from Wails' origin, so it can reach the bridge.
// Under `lgx dev` Wails proxies it from this dev server (HMR); otherwise
// `npm run build` / `npm run watch` write it to resources/public, which
// Wails serves (and embeds in a built binary).
export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: { "@": path.resolve(import.meta.dirname, "./src") },
  },
  base: "/",
  server: {
    // IPv4 explicitly, never "localhost": Node resolves that to ::1 on
    // macOS, but Wails' dev proxy dials localhost over IPv4 only, so every
    // page request failed and the window stayed blank. scripts/dev.sh
    // points FRONTEND_DEVSERVER_URL at the same address.
    host: "127.0.0.1",
    port: 5173,
    strictPort: true,
    // The HMR websocket goes straight to Vite. The page's own origin is
    // Wails' (wails://localhost:5173 on macOS, http://localhost:<port> in
    // server mode), and in server mode nothing there answers a websocket.
    ws: { protocol: "ws", host: "127.0.0.1", clientPort: 5173 },
  },
  build: {
    outDir: "../resources/public",
    emptyOutDir: true,
  },
});
