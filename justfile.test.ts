import { expect, test } from "bun:test"
import { copyFileSync, mkdtempSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import path from "node:path"

test("机器选择仅加载非机密配置并保留环境变量优先级", () => {
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
    const result = run(...args, "--command", "sh", "-c", 'printf "%s\\n" "$PROFILE"')
    expect(result.exitCode).toBe(0)
    return result.stdout.toString().trim()
  }
  try {
    copyFileSync(new URL("./justfile", import.meta.url), path.join(cwd, "justfile"))
    writeFileSync(path.join(cwd, ".host-profile"), "")
    expect(run("--list").exitCode).toBe(0)
    writeFileSync(path.join(cwd, ".host-profile"), "PROFILE=demo-a\n")
    writeFileSync(path.join(cwd, ".env"), "PROFILE=secret-file-host\n")
    expect(profile()).toBe("demo-a")
    env.PROFILE = "demo-b"
    expect(profile()).toBe("demo-b")
  } finally {
    rmSync(cwd, { recursive: true })
  }
})
