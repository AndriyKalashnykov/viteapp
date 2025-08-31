import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { resolve } from "node:path";

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      "@": resolve(__dirname, "src"),
    },
  },
  build: {
    target: "ES2022",
    minify: "terser",
    terserOptions: {
      compress: {
        drop_console: true,
        drop_debugger: true,
      },
    },
    commonjsOptions: {
      transformMixedEsModules: true,
    },
        rollupOptions: {
      output: {
        manualChunks: {
          // vendor split examples
          react: ["react", "react-dom"],
          router: ["react-router-dom"],
        },
        // or dynamic grouping:
        // manualChunks(id) {
        //   if (id.includes("node_modules")) {
        //     if (id.includes("react")) return "react";
        //     if (id.includes("react-router")) return "router";
        //     return "vendor";
        //   }
        // }
      },
    },
  },
});
