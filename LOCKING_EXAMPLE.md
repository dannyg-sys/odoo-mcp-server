import { existsSync, writeFileSync, unlinkSync, readFileSync } from "fs";
import { join } from "path";

class OdooLock {
  private lockFile: string;
  private maxLockAge: number = 300000; // 5 minutes

  constructor(config: OdooConfig, operation: string) {
    this.lockFile = join(config.root, `.odoo_mcp_${operation}.lock`);
  }

  acquire(): boolean {
    // Check if lock exists
    if (existsSync(this.lockFile)) {
      try {
        const lockData = JSON.parse(readFileSync(this.lockFile, "utf-8"));
        const lockAge = Date.now() - lockData.timestamp;
        
        // If lock is stale (older than 5 minutes), remove it
        if (lockAge > this.maxLockAge) {
          unlinkSync(this.lockFile);
        } else {
          return false; // Lock is active
        }
      } catch {
        // Invalid lock file, remove it
        unlinkSync(this.lockFile);
      }
    }

    // Acquire lock
    writeFileSync(
      this.lockFile,
      JSON.stringify({
        timestamp: Date.now(),
        pid: process.pid,
      })
    );
    return true;
  }

  release(): void {
    if (existsSync(this.lockFile)) {
      try {
        unlinkSync(this.lockFile);
      } catch {
        // Ignore errors on release
      }
    }
  }
}

// Usage in methods:
private async startOdoo(config: OdooConfig): Promise<any> {
  const lock = new OdooLock(config, "start");
  
  if (!lock.acquire()) {
    return {
      content: [{
        type: "text",
        text: "Another agent is currently starting Odoo. Please wait and try again.",
      }],
    };
  }

  try {
    const output = this.executeCommand(config, "./manage_odoo.sh start");
    return {
      content: [{
        type: "text",
        text: `Odoo started:\n${output}`,
      }],
    };
  } finally {
    lock.release();
  }
}
