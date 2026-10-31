/**
 * 重放 omp 会话中被 guard 拦截的工具调用，统计指定 guard 版本下仍拦截的规则分布。
 *
 * 用法：bun replay.ts <guard 模块路径> [--samples <规则>]
 * 规则即拒绝信息中 `command:` / `path:` 后的值，例如 --samples "rm -rf *"
 */
import { homedir } from "node:os";
import path from "node:path";

const args = process.argv.slice(2);
const sampleIdx = args.indexOf("--samples");
const sampleRule = sampleIdx === -1 ? undefined : args[sampleIdx + 1];
const target = args.find((a, i) => a !== "--samples" && (sampleIdx === -1 || i !== sampleIdx + 1));
if (target === undefined) throw new Error("用法：bun replay.ts <guard 模块路径> [--samples <规则>]");
const modulePath = path.resolve(target);
const sessionsDir = path.join(homedir(), ".omp/agent/sessions");

type Blocked = { tool: string; input: Record<string, unknown>; cwd: string };

function ruleOf(reason: string): string {
  return reason.match(/\n(?:path|command): ([^\n]*)/)?.[1] ?? reason.split("\n")[0];
}

// 会话文件由 omp 写入，只读取下列字段
type SessionMessage = {
  role?: string;
  toolCallId?: string;
  content?: Array<{ type?: string; id?: string; name?: string; arguments?: Record<string, unknown>; text?: string }>;
};

const files = Bun.spawnSync(["rg", "-l", "--no-messages", "! FORBIDDEN", sessionsDir, "--glob=*.jsonl"])
  .stdout.toString()
  .trim()
  .split("\n")
  .filter(Boolean);

const blocked: Blocked[] = [];
for (const file of files) {
  let cwd = "/tmp";
  const calls = new Map<string, { name: string; input: Record<string, unknown> }>();
  for (const line of (await Bun.file(file).text()).split("\n")) {
    if (!line) continue;
    let entry: unknown;
    try {
      entry = JSON.parse(line);
    } catch {
      continue;
    }
    if (typeof entry !== "object" || entry === null) continue;
    if ("type" in entry && entry.type === "session" && "cwd" in entry && typeof entry.cwd === "string") {
      cwd = entry.cwd;
    }
    const msg = "message" in entry && typeof entry.message === "object" ? (entry.message as SessionMessage | null) : null;
    if (msg?.role === "assistant" && Array.isArray(msg.content)) {
      for (const c of msg.content) {
        if (c.type === "toolCall" && c.id && c.name) calls.set(c.id, { name: c.name, input: c.arguments ?? {} });
      }
    }
    if (msg?.role !== "toolResult" || !msg.toolCallId) continue;
    const text = (msg.content ?? []).map((c) => c.text ?? "").join("");
    const call = calls.get(msg.toolCallId);
    if (text.startsWith("! FORBIDDEN") && call) blocked.push({ tool: call.name, input: call.input, cwd });
  }
}

// 待测 guard 版本由命令行参数指定，只能动态加载
const guard = await import(modulePath);
let handler: ((event: unknown, ctx: unknown) => unknown) | undefined;
guard.default({
  on: (event: string, h: typeof handler) => {
    if (event === "tool_call") handler = h;
  },
});
if (!handler) throw new Error(`${modulePath} 未注册 tool_call`);

const byRule = new Map<string, Blocked[]>();
for (const call of blocked) {
  const result = (await handler({ toolName: call.tool, input: call.input }, { cwd: call.cwd })) as
    | { block?: boolean; reason?: string }
    | undefined;
  if (!result?.block || !result.reason) continue;
  const key = `${result.reason.split("\n")[0]} | ${ruleOf(result.reason)}`;
  byRule.set(key, [...(byRule.get(key) ?? []), call]);
}

const stillBlocked = [...byRule.values()].reduce((n, list) => n + list.length, 0);
console.log(`历史拦截 ${blocked.length}，当前仍拦截 ${stillBlocked}`);
for (const [key, list] of [...byRule].sort((a, b) => b[1].length - a[1].length)) {
  console.log(`${list.length}\t${key}`);
}

if (sampleRule !== undefined) {
  console.log(`\n# ${sampleRule}`);
  for (const [key, list] of byRule) {
    if (!key.endsWith(`| ${sampleRule}`)) continue;
    for (const call of list) {
      const i = call.input;
      const text = String(i.command ?? i.path ?? (Array.isArray(i.paths) ? i.paths.join(";") : i.input ?? ""));
      console.log(`[${call.tool}] ${text.replace(/\s+/g, " ").slice(0, 200)}`);
    }
  }
}
