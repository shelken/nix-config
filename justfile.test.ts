import { expect, test } from "bun:test"
import { copyFileSync, existsSync, mkdtempSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import path from "node:path"

test("机器选择仅加载非机密配置并拒绝缺失的默认主机", () => {
  const just = Bun.which("just")
  if (!just) throw new Error("验证机器选择需要 just")
  const cwd = mkdtempSync(path.join(tmpdir(), "just-profile-"))
  const env = { ...process.env }
  delete env.PROFILE
  delete env.LOCAL_SECRETS_DIR
  // 隔离 Nix 工具，回归失败时也不能意外构建或切换机器
  env.PATH = "/usr/bin:/bin"
  const run = (...args: string[]) =>
    Bun.spawnSync([just, ...args], { cwd, env, stdout: "pipe", stderr: "pipe" })
  const profile = (...args: string[]) => {
    const result = run(...args, "--evaluate", "profile")
    expect(result.exitCode).toBe(0)
    return result.stdout.toString().trim()
  }
  try {
    copyFileSync(new URL("./justfile", import.meta.url), path.join(cwd, "justfile"))
    writeFileSync(path.join(cwd, ".host-profile"), "")
    expect(run("--list").exitCode).toBe(0)
    const missing = run("rebuild")
    expect(missing.exitCode).toBe(1)
    writeFileSync(path.join(cwd, ".host-profile"), "PROFILE=demo-a\n")
    writeFileSync(path.join(cwd, ".env"), "PROFILE=secret-file-host\n")
    expect(profile()).toBe("demo-a")
    env.PROFILE = "demo-b"
    expect(profile()).toBe("demo-b")
    expect(profile("--set", "profile", "demo-c")).toBe("demo-c")
    delete env.PROFILE
    writeFileSync(path.join(cwd, ".host-profile"), "PROFILE='demo-a; printf corrupted > marker'\n")
    run("rebuild")
    expect(existsSync(path.join(cwd, "marker"))).toBe(false)
    rmSync(path.join(cwd, ".host-profile"))
    expect(run("--dry-run", "rebuild", "demo-d").exitCode).toBe(0)
    expect(profile("--set", "profile", "demo-e")).toBe("demo-e")
  } finally {
    rmSync(cwd, { recursive: true })
  }
})
