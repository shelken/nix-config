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
