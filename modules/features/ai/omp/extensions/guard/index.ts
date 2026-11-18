/**
 * guard 的宿主入口：pi 与 omp 都加载本文件。判定逻辑在 guard.ts，
 * 宿主包只在这里 import，测试与重放脚本直接用 guard.ts，不依赖宿主运行时。
 */
import { CONFIG_DIR_NAME, getAgentDir, parseFrontmatter } from "@earendil-works/pi-coding-agent";
import { registerGuard, type GuardExtensionAPI } from "./guard.ts";

/**
 * 借宿主的 frontmatter 解析器解析整份 YAML：两个宿主都导出它，而 pi 跑在 Node 上没有 Bun.YAML，
 * omp 下又无法 import yaml 包。frontmatter 以 `---` 行为界，文件里出现这种行为会被截断，所以直接拒绝
 */
function parseYaml(source: string): unknown {
  if (/^---/m.test(source)) throw new Error("权限文件不能包含以 --- 开头的行");
  return parseFrontmatter(`---\n${source}\n---\n`).frontmatter;
}

export default function guard(pi: GuardExtensionAPI): void {
  registerGuard(pi, { agentDir: getAgentDir(), configDirName: CONFIG_DIR_NAME, parseYaml });
}
