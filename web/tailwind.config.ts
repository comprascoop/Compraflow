import type { Config } from "tailwindcss";
const config: Config = {
  content: ["./src/**/*.{ts,tsx}"],
  theme: { extend: {
    colors: {
      primary: { DEFAULT: "hsl(var(--primary))", fg: "hsl(var(--primary-fg))" },
      muted: "hsl(var(--muted))", border: "hsl(var(--border))",
    },
    borderRadius: { lg: "0.6rem", md: "0.45rem", sm: "0.3rem" },
  }},
  plugins: [],
};
export default config;
