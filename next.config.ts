import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Cloud Run 用に node_modules を含まない最小構成で出力する
  output: "standalone",
};

export default nextConfig;
