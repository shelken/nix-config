import { homedir } from "node:os";
import {
  BUILTIN_COMMAND_CONFIG,
  expandHomeInText,
  getPermissionPaths,
  loadPolicyFromPaths,
  normPath,
  pathRuleMatches,
  stripOmpSelector,
  type CommandRule,
  type LoadFailure,
  type PathRule,
  type Policy,
  type YamlParser,
} from "./policy.ts";
import {
  argvMatches,
  argvOf,
  basenames,
  commandNodes,
  downloadPipeExecutes,
  embeddedScripts,
  executesStdinProgram,
  lookup,
  operandWords,
  patternWords,
  scanSubsInText,
  stripWrapperWords,
  tokenizeShell,
  type ShellCmd,
  type ShellWord,
} from "./shell.ts";

export type { CommandRule, PathRule, Policy } from "./policy.ts";
export { buildPolicy } from "./policy.ts";

export type GuardInput =
  | { tool: "bash"; command: string; cwd: string; home: string }
  | { tool: string; path?: string; paths?: string[]; input?: string; cwd: string; home: string };

export type GuardResult = { block: false } | { block: true; reason: string };

type BuiltinHit = { rule: string; reason: string };
type Rule = { value: string; reason?: string; source: "builtin" | "user"; config: string };

const DYNAMIC_RE = /\$\{[^}]*\}|\$[A-Za-z_][A-Za-z0-9_]*|\$\d+|\$[*@#?!$-]/g;

function stripGlob(text: string): string {
  let out = "";
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (c === "*" || c === "?") continue;
    if (c === "[") {
      const close = text.indexOf("]", i + 1);
      if (close !== -1) {
        i = close;
        continue;
      }
    }
    out += c;
  }
  return out;
}

function dangerousRmTarget(word: ShellWord, home: string): string | null {
  if (word.value === "") return null;
  const literal = word.value.replace(DYNAMIC_RE, "");
  const globbed = word.glob ? stripGlob(literal) : literal;
  const skeleton = globbed.replace(/\/{2,}/g, "/");
  const base = skeleton.replace(/\/+$/, "").replace(/(?:\/\.)+$/, "");
  if (base === home) return "rm -rf ~";
  if (base === ".") return "rm -rf .";
  if (base === "..") return "rm -rf ..";
  if (base !== "") return null;
  if (literal === "") return null;
  return skeleton.startsWith("/") ? "rm -rf /" : "rm -rf *";
}

function rmHit(cmd: ShellCmd, home: string): BuiltinHit | null {
  const args = stripWrapperWords(cmd.words);
  if (args.length === 0 || basenames(args[0].value) !== "rm") return null;

  let force = false;
  let recursive = false;
  const targets: ShellWord[] = [];
  for (const word of args.slice(1)) {
    const value = word.value;
    if (value === "--recursive") recursive = true;
    else if (value === "--force") force = true;
    else if (value.startsWith("-") && !value.startsWith("--")) {
      for (const ch of value.slice(1)) {
        if (ch === "r" || ch === "R") recursive = true;
        else if (ch === "f") force = true;
      }
    } else if (!value.startsWith("-")) targets.push(word);
  }
  if (!force || !recursive) return null;

  for (const target of targets) {
    const rule = dangerousRmTarget(target, home);
    if (rule !== null) return { rule, reason: "禁止递归强制删除危险目标" };
  }
  return null;
}

function envHit(cmd: ShellCmd): BuiltinHit | null {
  const args = operandWords(cmd.words).map((w) => w.value);
  if (args.length === 0) return null;
  const head = basenames(args[0]);
  if (head === "env") return { rule: "env", reason: "禁止整体读取环境变量" };
  if (head === "printenv" && args.slice(1).every((a) => a.startsWith("-"))) {
    return { rule: "printenv", reason: "禁止整体读取环境变量" };
  }
  if (head === "export" && args.slice(1).every((a) => a === "-p")) {
    return { rule: args.length === 1 ? "export" : "export -p", reason: "禁止整体读取环境变量" };
  }
  return null;
}

function deviceHit(cmd: ShellCmd): BuiltinHit | null {
  const args = operandWords(cmd.words).map((w) => w.value);
  if (args.length === 0) return null;
  const head = basenames(args[0]).toLowerCase();
  if (head.startsWith("mkfs")) return { rule: "mkfs*", reason: "禁止裸设备写入" };
  if (head === "dd" && args.slice(1).some((a) => /^of=\/dev\//.test(a))) {
    return { rule: "dd of=/dev/*", reason: "禁止裸设备写入" };
  }
  return null;
}

function builtinCommandHit(cmd: ShellCmd, home: string): BuiltinHit | null {
  return rmHit(cmd, home) ?? envHit(cmd) ?? deviceHit(cmd);
}

const METADATA_HEADS: Record<string, true> = lookup<true>({
  ls: true,
  stat: true,
  test: true,
  "[": true,
  "[[": true,
  echo: true,
  printf: true,
});

function isMetadataCommand(cmd: ShellCmd): boolean {
  if (cmd.pipeNext) return false;
  const args = operandWords(cmd.words).map((w) => w.value);
  if (args.length === 0) return false;
  const head = basenames(args[0]);
  if (METADATA_HEADS[head] === true) return true;
  return head === "git" && args[1] === "check-ignore";
}

function matchingPathRule(candidate: string, policy: Policy, cwd: string, home: string): PathRule | undefined {
  const absolute = normPath(candidate, cwd, home);
  return policy.paths.find((rule) => pathRuleMatches(rule, absolute));
}

function bashPathHit(nodes: ShellCmd[], policy: Policy, cwd: string, home: string): PathRule | undefined {
  for (const cmd of nodes) {
    const metadata = isMetadataCommand(cmd);
    for (const word of cmd.words) {
      if (word.target === null && metadata) continue;
      const token = word.value;
      const pathLike =
        token !== "" &&
        !token.startsWith("-") &&
        (token.includes("/") || token === ".env" || token.startsWith(".env."));
      if (!pathLike) continue;
      const rule = matchingPathRule(token, policy, cwd, home);
      if (rule) return rule;
    }
  }
  return undefined;
}

/** Hashline Edit 的块头与 MV 目标同样是被改写的路径 */
function extractEditPaths(input: string): string[] {
  const paths = new Set<string>();
  const headerRe = /^\s*\[([^\]\r\n#]+)(?:#[0-9a-fA-F]{4})?\]/gm;
  const mvRe = /^\s*MV\s+(?:"([^"\r\n]+)"|'([^'\r\n]+)'|(\S+))/gm;
  let m: RegExpExecArray | null;
  while ((m = headerRe.exec(input)) !== null) {
    if (m[1]?.trim()) paths.add(m[1].trim());
  }
  while ((m = mvRe.exec(input)) !== null) {
    const dest = m[1] || m[2] || m[3];
    if (dest?.trim()) paths.add(dest.trim());
  }
  return [...paths];
}

function resolveBlockReason(rule: Rule, kind: "command" | "path", defaultReason?: string): string {
  const reason = rule.source === "user" ? rule.reason || defaultReason : rule.reason;
  const detail = reason?.split(/\r\n|\r|\n/).join(" ").trim();
  const header = rule.source === "user" ? "BY USER" : kind === "command" ? "COMMAND" : "PATH";
  const lines = [`! FORBIDDEN ${header}`, `${kind}: ${rule.value}`, `config: ${rule.config}`];
  if (detail) lines.push(`reason: ${detail}`);
  return lines.join("\n");
}

/** Git 全局选项；带独立取值的选项连同后一个词一起跳过 */
const GIT_GLOBAL_VALUE_OPTIONS: Record<string, true> = lookup<true>({
  "-C": true,
  "-c": true,
  "--git-dir": true,
  "--work-tree": true,
  "--namespace": true,
  "--config-env": true,
  "--super-prefix": true,
});

function gitAddIsFullScope(words: ShellWord[]): boolean {
  const args = operandWords(words);
  const argv = args.map((w) => w.value);
  if (basenames(argv[0] ?? "") !== "git") return false;

  let i = 1;
  while (i < argv.length && argv[i].startsWith("-")) {
    i += GIT_GLOBAL_VALUE_OPTIONS[argv[i]] === true ? 2 : 1;
  }
  if (argv[i] !== "add") return false;

  let preview = false;
  let indirect = false;
  let fullScope = false;
  let hasPaths = false;
  let afterSeparator = false;
  for (const word of args.slice(i + 1)) {
    const arg = word.value;
    if (!afterSeparator && arg === "--") {
      afterSeparator = true;
      continue;
    }
    if (!afterSeparator && arg.startsWith("-")) {
      if (arg === "--patch" || arg === "--interactive" || arg === "--dry-run" || /^-[a-zA-Z]*[pin]/.test(arg)) {
        preview = true;
        continue;
      }
      if (arg === "--pathspec-from-file" || arg.startsWith("--pathspec-from-file=")) indirect = true;
      continue;
    }
    hasPaths = true;
    const normalized = arg.replace(/\/{2,}/g, "/").replace(/\/+$/, "");
    if (word.dynamic || word.glob || arg === ":/") fullScope = true;
    else if (normalized === "" || normalized === "." || normalized === "..") fullScope = true;
  }
  if (preview) return false;
  if (indirect || fullScope) return true;
  return !hasPaths;
}

function commandRuleMatches(nodes: ShellCmd[], rule: CommandRule): boolean {
  const words = patternWords(rule.match);
  if (!words) return false;
  const gitAddRule =
    words.length === 3 && words[0] === "git" && words[1] === "add" && (words[2] === "-A" || words[2] === ".");
  return nodes.some((cmd) =>
    gitAddRule ? gitAddIsFullScope(cmd.words) : argvMatches(argvOf(cmd), words),
  );
}

function heredocScript(token: { value: string; quoted: boolean; owner: number }, nodes: ShellCmd[]): string {
  let owner = 0;
  for (let i = 0; i < nodes.length; i++) {
    if (nodes[i].startToken <= token.owner) owner = i;
  }
  for (let i = owner; i < nodes.length; i++) {
    if (executesStdinProgram(nodes[i].words, true)) return token.value;
    if (!nodes[i].pipeNext) break;
  }
  return token.quoted ? "" : scanSubsInText(token.value).join("\n");
}

function evaluateBash(
  input: { command: string; cwd: string; home: string },
  policy: Policy,
): GuardResult {
  const command = expandHomeInText(input.command, input.home);
  const tokens = tokenizeShell(command);
  const nodes = commandNodes(tokens);
  const blocked = (rule: Rule, kind: "command" | "path"): GuardResult => ({
    block: true,
    reason: resolveBlockReason(rule, kind, policy.default_reason),
  });
  const builtin = (hit: BuiltinHit): Rule => ({
    value: hit.rule,
    reason: hit.reason,
    source: "builtin",
    config: BUILTIN_COMMAND_CONFIG,
  });

  for (const cmd of nodes) {
    const hit = builtinCommandHit(cmd, input.home);
    if (hit) return blocked(builtin(hit), "command");
  }

  const download = downloadPipeExecutes(nodes);
  if (download) {
    return blocked(
      builtin({
        rule: `${download.downloader} | ${download.interpreter}`,
        reason: "禁止把网络下载内容直接交给 shell 或解释器执行",
      }),
      "command",
    );
  }

  for (const rule of policy.commands) {
    if (commandRuleMatches(nodes, rule)) return blocked(rule, "command");
  }

  const pathRule = bashPathHit(nodes, policy, input.cwd, input.home);
  if (pathRule) return blocked(pathRule, "path");

  const nested = (script: string): GuardResult | undefined => {
    const result = evaluateBash({ command: script, cwd: input.cwd, home: input.home }, policy);
    return result.block ? result : undefined;
  };
  for (const token of tokens) {
    if (token.kind !== "sub" && token.kind !== "heredoc") continue;
    const script = token.kind === "sub" ? token.value : heredocScript(token, nodes);
    const result = script === "" ? undefined : nested(script);
    if (result) return result;
  }
  for (const script of embeddedScripts(nodes.map(argvOf))) {
    const result = nested(script);
    if (result) return result;
  }
  return { block: false };
}

export function evaluateGuard(input: GuardInput, policy: Policy): GuardResult {
  if (input.tool === "bash") return evaluateBash(input, policy);

  const candidates = new Set<string>();
  const add = (raw: string) => {
    for (const seg of raw.includes(";") ? raw.split(";") : [raw]) {
      if (seg.trim() !== "") candidates.add(seg.trim());
    }
  };
  if (typeof input.path === "string") add(input.path);
  for (const p of input.paths ?? []) add(p);
  if (typeof input.input === "string") {
    for (const p of extractEditPaths(input.input)) add(p);
  }

  for (const raw of candidates) {
    const expanded = expandHomeInText(raw, input.home);
    const candidate = input.tool === "read" ? stripOmpSelector(expanded) : expanded;
    const rule = matchingPathRule(candidate, policy, input.cwd, input.home);
    if (rule) {
      return { block: true, reason: resolveBlockReason(rule, "path", policy.default_reason) };
    }
  }
  return { block: false };
}

export interface GuardExtensionContext {
  cwd: string;
  hasUI?: boolean;
  ui?: { notify?: (message: string, type?: "info" | "warning" | "error") => void; [key: string]: unknown };
  [key: string]: unknown;
}

export interface GuardExtensionAPI {
  on(
    event: "session_start",
    handler: (event: unknown, ctx: GuardExtensionContext) => void,
  ): void;
  on(
    event: "tool_call",
    handler: (
      event: { toolName: string; input?: Record<string, unknown> },
      ctx: GuardExtensionContext,
    ) => { block: true; reason: string } | undefined,
  ): void;
  [key: string]: unknown;
}

export interface GuardHost {
  agentDir: string;
  configDirName: string;
  parseYaml: YamlParser;
}

export function registerGuard(pi: GuardExtensionAPI, host: GuardHost): void {
  const policyCache = new Map<string, Policy>();
  const notified = new Set<string>();

  function reportFailures(ctx: GuardExtensionContext, failures: LoadFailure[]): void {
    for (const failure of failures) {
      const msg =
        failure.scope === "layer"
          ? `guard: 无法加载配置 ${failure.path}: ${failure.message}；该层已忽略（fail-open）`
          : `guard: 配置 ${failure.path}: ${failure.message}；该项已忽略`;
      // TUI 占着终端时直接写 stderr 会弄花界面，所以有 UI 时只走通知
      if (ctx.hasUI && ctx.ui?.notify) {
        if (notified.has(msg)) continue;
        notified.add(msg);
        ctx.ui.notify(msg, "error");
      } else {
        console.error(msg);
      }
    }
  }

  function ensurePolicy(ctx: GuardExtensionContext): Policy {
    const cached = policyCache.get(ctx.cwd);
    if (cached) return cached;
    const loaded = loadPolicyFromPaths(getPermissionPaths(ctx.cwd, host.agentDir, host.configDirName), {
      home: homedir(),
      cwd: ctx.cwd,
      parseYaml: host.parseYaml,
    });
    policyCache.set(ctx.cwd, loaded.policy);
    reportFailures(ctx, loaded.failures);
    return loaded.policy;
  }

  pi.on("session_start", (_event, ctx) => {
    policyCache.clear();
    notified.clear();
    ensurePolicy(ctx);
  });

  pi.on("tool_call", (event, ctx) => {
    const policy = ensurePolicy(ctx);
    const input = event.input ?? {};
    const text = (v: unknown) => (typeof v === "string" ? v : undefined);

    const call: GuardInput =
      event.toolName === "bash"
        ? { tool: "bash", command: text(input.command) ?? "", cwd: ctx.cwd, home: homedir() }
        : {
            tool: event.toolName,
            path: text(input.path),
            paths: Array.isArray(input.paths)
              ? input.paths.filter((p): p is string => typeof p === "string")
              : undefined,
            input: text(input.input),
            cwd: ctx.cwd,
            home: homedir(),
          };

    const result = evaluateGuard(call, policy);
    return result.block ? { block: true, reason: result.reason } : undefined;
  });
}
