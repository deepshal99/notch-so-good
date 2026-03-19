#!/usr/bin/env node

// Notch So Good — npx installer
// Downloads and runs the shell installer which handles everything.

import { execSync } from "child_process";
import { platform } from "os";

if (platform() !== "darwin") {
  console.error("Notch So Good only works on macOS.");
  process.exit(1);
}

const installerUrl =
  "https://raw.githubusercontent.com/deepshal99/notch-so-good/main/get.sh";

try {
  execSync(`curl -fsSL "${installerUrl}" | bash`, {
    stdio: "inherit",
    shell: "/bin/bash",
  });
} catch (err) {
  process.exit(err.status || 1);
}
