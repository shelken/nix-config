/**
 * omp-guard — Oh My Pi (OMP) 原生安全防护扩展。
 *
 * 核心防护能力：
 * 1. Shell 词法深度解析与复合命令解构（支持 ;, |, &&, ||, 子 shell, eval, sh -c, 反引号与 $() 命令替换）；
 * 2. 进程包装器与环境变量剥离（自动剥离 sudo, nohup, env, time, timeout 等前缀，并规范化 rm 参数标志位）；
 * 3. 危险删除与全局遍历指令硬阻断（rm -rf /, find /, env, printenv, export -p, curl|bash, wget|sh 等）；
 * 4. 机密文件与凭据路径硬阻断（~/.ssh, 云厂商凭据, Token, .env, 历史文件等）；
 * 5. OMP Hashline Edit 补丁块深度审计（提取 [file#tag] 块头及 MV 重命名目标）；
 * 6. ast_edit 与多路径工具（grep/glob 分号列表）深度过滤；
 * 7. 声明式 YAML 多层策略继承（内置规则 -> 全局 permissions.yml -> 项目级 permissions.yml，按 CWD 缓存）；
 * 8. 零外部 npm 依赖，完全兼容 Bun 与 Node 原生环境。
 */

import { existsSync, readFileSync, realpathSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";

// ============================================================================
// 类型定义 (Types)
// ============================================================================

export type Rule = {
  value: string;
  reason?: string;
  source?: "builtin" | "user";
};

export type Policy = {
  default_reason?: string;
  commands: Rule[];
  paths: Rule[];
};

/** 判别联合类型：确保不同工具输入参数在类型系统层级完全收窄 */
export type GuardInput =
  | {
      tool: "bash";
      command: string;
      cwd: string;
      home: string;
    }
  | {
      tool: "read" | "write" | "edit" | "ast_edit" | string;
      path?: string;
      paths?: string[];
      input?: string;
      cwd: string;
      home: string;
    };

export type GuardResult =
  | { block: false }
  | { block: true; reason: string };

export type LayerOp =
  | { type: "add"; value: string; reason?: string }
  | { type: "remove"; value: string };

export type ParsedLayer = {
  default_reason?: string;
  commandOps: LayerOp[];
  pathOps: LayerOp[];
  errors: string[];
};

export type ParseLayerResult =
  | { ok: true; layer: ParsedLayer }
  | { ok: false; error: string };

export type BuildPolicyResult = {
  policy: Policy;
  errors: string[];
};

export type PermissionPaths = {
  globalPath: string;
  projectPath: string;
};

export type LoadFailure = {
  path: string;
  message: string;
};

export type LoadPolicyResult = {
  policy: Policy;
  failures: LoadFailure[];
};

export type ReadConfigResult =
  | { status: "missing" }
  | { status: "ok"; text: string }
  | { status: "error"; message: string };

export interface ExtensionContext {
  cwd: string;
  hasUI?: boolean;
  ui?: {
    notify?: (message: string, type?: "info" | "warning" | "error") => void;
    showWarning?: (message: string) => void;
    showStatus?: (message: string) => void;
  };
  [key: string]: unknown;
}

export type ToolCallEvent = {
  type?: "tool_call";
  toolName: string;
  toolCallId?: string;
  input?: Record<string, unknown>;
};

export type ToolCallResult =
  | { block: true; reason: string }
  | undefined
  | void;

export interface ExtensionAPI {
  on(
    event: "session_start",
    handler: (event: unknown, ctx: ExtensionContext) => void | Promise<void>,
  ): void;
  on(
    event: "tool_call",
    handler: (
      event: ToolCallEvent,
      ctx: ExtensionContext,
    ) => ToolCallResult | Promise<ToolCallResult>,
  ): void;
  [key: string]: unknown;
}

// ============================================================================
// 内置防护默认规则 (Built-in Defaults)
// ============================================================================

export const BUILTIN_COMMANDS: Rule[] = [
  // --- 破坏性文件系统递归删除 ---
  { value: "rm -rf /", reason: "禁止根目录递归强制删除", source: "builtin" },
  { value: "rm -rf ~", reason: "禁止家目录递归强制删除", source: "builtin" },
  { value: "rm -rf *", reason: "禁止全量通配递归强制删除", source: "builtin" },
  { value: "rm -rf ./*", reason: "禁止全量通配递归强制删除", source: "builtin" },
  { value: "rm -rf .*", reason: "禁止全量通配递归强制删除", source: "builtin" },
  { value: "rm -rf /*", reason: "禁止根目录通配递归强制删除", source: "builtin" },
  // --- 全盘遍历与耗尽 ---
  { value: "find /", reason: "禁止根目录全盘遍历", source: "builtin" },
  { value: "find ~", reason: "禁止家目录全盘遍历", source: "builtin" },
  // --- 破坏性磁盘裸写与低级格式化 ---
  { value: "dd of=/dev/*", reason: "禁止裸设备覆盖写入", source: "builtin" },
  { value: "mkfs*", reason: "禁止磁盘低级格式化", source: "builtin" },
  // --- 环境变量全量 dump 泄露（允许有参查询如 printenv PATH）---
  { value: "env", reason: "禁止直接批量读取环境变量", source: "builtin" },
  { value: "printenv", reason: "禁止直接批量读取环境变量", source: "builtin" },
  { value: "export", reason: "禁止直接批量读取环境变量", source: "builtin" },
  { value: "export -p", reason: "禁止直接批量读取环境变量", source: "builtin" },
  // --- 未落盘管道下载并直接交付 Shell / 解释器执行 ---
  { value: "curl *|*sh*", reason: "禁止网络下载直接管道执行", source: "builtin" },
  { value: "curl *| *sh*", reason: "禁止网络下载直接管道执行", source: "builtin" },
  { value: "wget *|*sh*", reason: "禁止网络下载直接管道执行", source: "builtin" },
  { value: "wget *| *sh*", reason: "禁止网络下载直接管道执行", source: "builtin" },
  { value: "curl *|*python*", reason: "禁止网络下载直接管道执行", source: "builtin" },
  { value: "curl *| *python*", reason: "禁止网络下载直接管道执行", source: "builtin" },
  { value: "wget *|*python*", reason: "禁止网络下载直接管道执行", source: "builtin" },
  { value: "wget *| *python*", reason: "禁止网络下载直接管道执行", source: "builtin" },
];

export const BUILTIN_PATHS: Rule[] = [
  // --- SSH 私钥与主机密钥 ---
  { value: "~/.ssh", source: "builtin" },
  { value: "~/.ssh/*", source: "builtin" },
  // --- 主流云厂商机密凭据主目录 ---
  { value: "~/.aws", source: "builtin" },
  { value: "~/.aws/*", source: "builtin" },
  { value: "~/.azure", source: "builtin" },
  { value: "~/.azure/*", source: "builtin" },
  { value: "~/.gcp", source: "builtin" },
  { value: "~/.gcp/*", source: "builtin" },
  // --- GnuPG 钥匙环 ---
  { value: "~/.gnupg", source: "builtin" },
  { value: "~/.gnupg/*", source: "builtin" },
  // --- SOPS age 私钥 ---
  { value: "~/.config/sops/age", source: "builtin" },
  { value: "~/.config/sops/age/*", source: "builtin" },
  // --- 通用认证与令牌配置 ---
  { value: "~/.netrc", source: "builtin" },
  { value: "~/.pypirc", source: "builtin" },
  { value: "~/.git-credentials", source: "builtin" },
  { value: "~/.config/gh/hosts.yml", source: "builtin" },
  { value: "~/.kube/config", source: "builtin" },
  { value: "~/.docker/config.json", source: "builtin" },
  // --- 终端与各类解释器交互历史统一拦截 ---
  { value: "~/.bash_history", source: "builtin" },
  { value: "~/.zsh_history", source: "builtin" },
  { value: "~/.zhistory", source: "builtin" },
  { value: "~/.node_repl_history", source: "builtin" },
  { value: "~/.python_history", source: "builtin" },
  // --- 环境变量机密文件 ---
  { value: ".env", source: "builtin" },
  { value: ".env.*", source: "builtin" },
  { value: "**/.env", source: "builtin" },
  { value: "**/.env.*", source: "builtin" },
];

// ============================================================================
// Shell 词法分析与分词引擎 (Shell Lexing & Parsing)
// ============================================================================

type ShellToken =
  | { kind: "word"; value: string }
  | { kind: "op"; value: string };

const CONTROL_OPS: Record<string, true> = {
  "|": true,
  "||": true,
  "&&": true,
  ";": true,
  "&": true,
  "\n": true,
  "(": true,
  ")": true,
};

export function tokenizeShell(input: string): ShellToken[] {
  const tokens: ShellToken[] = [];
  let i = 0;
  while (i < input.length) {
    const ch = input[i];
    if (ch === " " || ch === "\t" || ch === "\r") {
      i++;
      continue;
    }
    if (ch === "\n") {
      tokens.push({ kind: "op", value: "\n" });
      i++;
      continue;
    }
    if (input.startsWith("||", i) || input.startsWith("&&", i)) {
      tokens.push({ kind: "op", value: input.slice(i, i + 2) });
      i += 2;
      continue;
    }
    if (ch === "|" || ch === ";" || ch === "&" || ch === "(" || ch === ")") {
      tokens.push({ kind: "op", value: ch });
      i++;
      continue;
    }
    const redir = input.slice(i).match(/^(\d*)(>>|<<|<|>)/);
    if (redir) {
      tokens.push({ kind: "op", value: redir[0] });
      i += redir[0].length;
      continue;
    }

    let word = "";
    while (i < input.length) {
      const c = input[i];
      if (
        c === " " ||
        c === "\t" ||
        c === "\r" ||
        c === "\n" ||
        c === "|" ||
        c === ";" ||
        c === "&" ||
        c === "(" ||
        c === ")" ||
        c === "<" ||
        c === ">"
      ) {
        break;
      }
      if (input.startsWith("||", i) || input.startsWith("&&", i)) break;

      if (c === "'") {
        i++;
        while (i < input.length && input[i] !== "'") word += input[i++];
        if (i < input.length) i++;
        continue;
      }
      if (c === '"') {
        i++;
        while (i < input.length && input[i] !== '"') {
          if (input[i] === "\\" && i + 1 < input.length) {
            word += input[i + 1];
            i += 2;
            continue;
          }
          word += input[i++];
        }
        if (i < input.length) i++;
        continue;
      }
      if (c === "\\" && i + 1 < input.length) {
        word += input[i + 1];
        i += 2;
        continue;
      }
      word += c;
      i++;
    }
    tokens.push({ kind: "word", value: word });
  }
  return tokens;
}

/**
 * 将 Token 拆分为独立命令的 argv 列表。
 * 注意：重定向操作符（如 <, >, >>）后的文件名必须保留在当前 argv 中，
 * 保证路径匹配引擎能捕获 `cat < .env` 等重定向注入操作。
 */
export function simpleCommandArgvs(tokens: ShellToken[]): string[][] {
  const out: string[][] = [];
  let current: string[] = [];
  for (let i = 0; i < tokens.length; i++) {
    const t = tokens[i];
    if (t.kind === "op") {
      if (CONTROL_OPS[t.value]) {
        if (current.length > 0) out.push(current);
        current = [];
        continue;
      }
      // 重定向操作符：跳过操作符自身，后随的目标文件作为路径 token 进入 current argv
      continue;
    }
    current.push(t.value);
  }
  if (current.length > 0) out.push(current);
  return out;
}

function stripLeadingAssignments(words: string[]): string[] {
  let i = 0;
  while (i < words.length && /^[A-Za-z_][A-Za-z0-9_]*=/.test(words[i])) i++;
  return words.slice(i);
}

const FLAG_WRAPPERS: Record<string, true> = {
  nohup: true,
  command: true,
  builtin: true,
  exec: true,
  setsid: true,
  stdbuf: true,
  ionice: true,
  watch: true,
  xargs: true,
  time: true,
};

export function basenames(word: string): string {
  if (word === "/" || word === "." || word === "..") return word;
  const slash = word.lastIndexOf("/");
  return slash === -1 ? word : word.slice(slash + 1);
}

/** 剥离包装器命令（如 sudo, env, nohup, timeout 等） */
export function stripWrappers(words: string[]): string[] {
  let w = stripLeadingAssignments(words);
  for (;;) {
    if (w.length === 0) return w;
    const head = basenames(w[0]);

    if (head === "env") {
      let j = 1;
      while (j < w.length && w[j].startsWith("-")) {
        const f = w[j];
        if (
          f === "-u" ||
          f === "--unset" ||
          f === "-C" ||
          f === "--chdir" ||
          f === "-S" ||
          f === "--split-string"
        ) {
          j += 2;
        } else {
          j++;
        }
      }
      while (j < w.length && /^[A-Za-z_][A-Za-z0-9_]*=/.test(w[j])) j++;
      if (j >= w.length) return w;
      w = stripLeadingAssignments(w.slice(j));
      continue;
    }

    if (head === "sudo" || head === "doas") {
      let j = 1;
      while (j < w.length && w[j].startsWith("-")) {
        const f = w[j];
        if (f === "--") {
          j++;
          break;
        }
        if (
          f === "-u" ||
          f === "-g" ||
          f === "-p" ||
          f === "--user" ||
          f === "--group" ||
          f === "--prompt"
        ) {
          j += 2;
        } else {
          j++;
        }
      }
      w = stripLeadingAssignments(w.slice(j));
      continue;
    }

    if (head === "timeout") {
      let j = 1;
      while (j < w.length && w[j].startsWith("-")) {
        const f = w[j];
        if (
          f === "-k" ||
          f === "--kill-after" ||
          f === "-s" ||
          f === "--signal"
        ) {
          j += 2;
        } else {
          j++;
        }
      }
      if (j < w.length) j++;
      w = stripLeadingAssignments(w.slice(j));
      continue;
    }

    if (head === "nice") {
      let j = 1;
      if (j < w.length && (w[j] === "-n" || w[j] === "--adjustment")) {
        j += 2;
      } else if (j < w.length && /^-\d+$/.test(w[j])) {
        j++;
      }
      w = stripLeadingAssignments(w.slice(j));
      continue;
    }

    if (FLAG_WRAPPERS[head]) {
      let j = 1;
      while (j < w.length && w[j].startsWith("-")) j++;
      w = stripLeadingAssignments(w.slice(j));
      continue;
    }

    return w;
  }
}

/** 规范化 rm 命令的标志位组合，将各类 -fr, -r -f, --force --recursive 统合为 -rf */
function normalizeRmArgv(argv: string[]): string[] {
  if (argv.length === 0) return argv;
  const head = basenames(argv[0]);
  if (head !== "rm") return argv;

  let hasR = false;
  let hasF = false;
  const rest: string[] = [];

  for (let i = 1; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--recursive") {
      hasR = true;
    } else if (arg === "--force") {
      hasF = true;
    } else if (arg.startsWith("-") && !arg.startsWith("--") && arg.length > 1) {
      let otherFlags = "";
      for (let j = 1; j < arg.length; j++) {
        const ch = arg[j];
        if (ch === "r" || ch === "R") hasR = true;
        else if (ch === "f") hasF = true;
        else otherFlags += ch;
      }
      if (otherFlags) rest.push(`-${otherFlags}`);
    } else {
      rest.push(arg);
    }
  }

  if (hasR && hasF) {
    return [argv[0], "-rf", ...rest];
  }
  return argv;
}

function patternWordsOf(pattern: string): string[] | null {
  const tokens = tokenizeShell(pattern);
  if (tokens.some((t) => t.kind === "op" && CONTROL_OPS[t.value])) {
    return null;
  }
  const words = simpleCommandArgvs(tokens)[0] ?? [];
  return words.length > 0 ? words : null;
}

function isUnconstrainedEnvDump(argv: string[]): boolean {
  if (argv.length === 0) return false;
  const head = basenames(argv[0]);
  if (head === "printenv") {
    // 若没有参数，或仅有 -0/--null 等标志位而没有指定具体变量名，则为全量 dump
    const nonFlags = argv.slice(1).filter((a) => !a.startsWith("-"));
    return nonFlags.length === 0;
  }
  if (head === "export") {
    // 若没有参数，或仅有 -p，则为全量 dump
    if (argv.length === 1) return true;
    const nonFlags = argv.slice(1).filter((a) => a !== "-p");
    return nonFlags.length === 0;
  }
  return false;
}

function argvStartsWith(argv: string[], patternWords: string[]): boolean {
  const normArgv = normalizeRmArgv(argv);
  if (normArgv.length === 0) return false;

  const head = basenames(normArgv[0]);
  if (patternWords[0] === "printenv" && head === "printenv") {
    return isUnconstrainedEnvDump(normArgv);
  }
  if (patternWords[0] === "export" && head === "export") {
    return isUnconstrainedEnvDump(normArgv);
  }
  if (patternWords[0] === "dd" && head === "dd") {
    if (patternWords.some((p) => p.startsWith("of=/dev/"))) {
      return normArgv.some((a) => /^of=\/dev\//.test(a));
    }
  }

  // rm -rf 通配类规则（如 "rm -rf *"、"rm -rf ./*"、"rm -rf /*"）：
  // 只有当真实删除目标中含有 shell 通配符（* ? [）时才命中，
  // 避免把「定向删除具体路径/文件」（如 rm -rf /tmp/x）误判为全量通配清空。
  const isRmForceGlobPattern =
    head === "rm" &&
    normArgv[1] === "-rf" &&
    patternWords[1] === "-rf" &&
    patternWords.slice(2).some((w) => /[*?\[]/.test(w));
  if (isRmForceGlobPattern) {
    const targets = normArgv.slice(2).filter((t) => !t.startsWith("-"));
    return targets.some((t) => /[*?\[]/.test(t));
  }

  if (normArgv.length < patternWords.length) return false;
  for (let i = 0; i < patternWords.length; i++) {
    const a = normArgv[i];
    const p = patternWords[i];
    if (p.includes("*")) {
      const re = new RegExp(`^${globToRegExpSource(p)}$`);
      if (re.test(a)) continue;
      if (i === 0 && re.test(basenames(a))) continue;
      return false;
    }
    if (i === 0) {
      if (a !== p && basenames(a) !== p) return false;
      continue;
    }
    if (a === p) continue;
    if (a.startsWith(p) && /^[*?[\]]*$/.test(a.slice(p.length))) {
      continue;
    }
    return false;
  }
  return true;
}

export function commandMatchesPattern(
  command: string,
  pattern: string,
): boolean {
  // 结构性检测：curl/wget 未落盘直接管道交付 Shell / 解释器执行即命中，
  // 必须在下方通配正则分支之前判定，否则含 * 与 | 的规则会提前 return 使其失效
  if (
    pattern.includes("curl") ||
    pattern.includes("wget")
  ) {
    if (
      /\b(curl|wget)\b[^|;&]*\|[^|;&]*\b(bash|ash|zsh|dash|sh|python\d*|node|bun|perl|ruby)\b/i.test(
        command,
      )
    ) {
      return true;
    }
  }
  if (pattern.includes("*") && /[|;&\n]/.test(pattern)) {
    return new RegExp(globToRegExpSource(pattern), "i").test(command);
  }
  const argvs = simpleCommandArgvs(tokenizeShell(command));
  const patternWords = patternWordsOf(pattern);
  if (!patternWords) {
    if (pattern.includes("*")) {
      return new RegExp(globToRegExpSource(pattern)).test(command);
    }
    return false;
  }
  for (const argv of argvs) {
    if (argvStartsWith(stripWrappers(argv), patternWords)) return true;
  }
  return false;
}

/** 提取嵌套在 shell wrapper（如 sh -c, bash -lc, eval, 反引号, $()）中的内嵌脚本 */
function embeddedScripts(argvs: string[][], rawCommand?: string): string[] {
  const scripts: string[] = [];
  const shells = new Set(["sh", "bash", "dash", "zsh", "ash"]);
  for (const argv of argvs) {
    const stripped = stripWrappers(argv);
    if (stripped.length === 0) continue;
    const head = basenames(stripped[0]);
    if (shells.has(head)) {
      const cIdx = stripped.findIndex(
        (arg, idx) => idx > 0 && /^-[a-zA-Z]*c[a-zA-Z]*$/.test(arg),
      );
      if (cIdx !== -1 && cIdx + 1 < stripped.length) {
        scripts.push(stripped[cIdx + 1]);
      }
      continue;
    }
    if (head === "eval") {
      for (let i = 1; i < stripped.length; i++) {
        if (stripped[i].startsWith("-")) continue;
        scripts.push(stripped.slice(i).join(" "));
        break;
      }
    }
  }

  // 递归扫描提取反引号及 $() 内部的命令替换
  if (rawCommand) {
    const backtickRe = /`([^`]+)`/g;
    let bm: RegExpExecArray | null;
    while ((bm = backtickRe.exec(rawCommand)) !== null) {
      if (bm[1]?.trim()) scripts.push(bm[1].trim());
    }

    const dollarParenRe = /\$\(([^)]+)\)/g;
    let dm: RegExpExecArray | null;
    while ((dm = dollarParenRe.exec(rawCommand)) !== null) {
      if (dm[1]?.trim()) scripts.push(dm[1].trim());
    }
  }

  return scripts;
}

// ============================================================================
// 路径规范化与匹配引擎 (Path Normalization & Matching)
// ============================================================================

export function globToRegExpSource(pattern: string): string {
  // 折叠连续通配符（**）防止 ReDoS 正则回溯漏洞
  const collapsed = pattern.replace(/\*{2,}/g, "*");
  let out = "";
  for (const ch of collapsed) {
    if (ch === "*") {
      out += ".*";
      continue;
    }
    if (/[\\^$+?.()|[\]{}]/.test(ch)) {
      out += `\\${ch}`;
      continue;
    }
    out += ch;
  }
  return out;
}

export function expandHomeInText(text: string, home: string): string {
  if (!home) return text;
  let s = text.replaceAll("${HOME}", home);
  s = s.replace(/\$HOME\b/g, home);
  s = s.replace(
    /(^|[^A-Za-z0-9_])~(?=\/|$|[^A-Za-z0-9_/])/g,
    (_m, pre: string) => pre + home,
  );
  return s;
}

/**
 * 剥离 OMP 工具行锚定与格式选择器（如 :50-200, :raw, :conflicts, :10:raw 等）。
 * 针对首个选择器冒号截断，并兼容 Windows 盘符（如 C:\）。
 */
export function stripOmpSelector(p: string): string {
  const startIdx =
    process.platform === "win32" && /^[a-zA-Z]:/.test(p) ? 2 : 0;
  const colonIdx = p.indexOf(":", startIdx);
  if (colonIdx > 0) {
    return p.slice(0, colonIdx);
  }
  return p;
}

export function normPath(p: string, cwd: string, home: string): string {
  const t = expandHomeInText(p.trim(), home);
  return path.normalize(path.resolve(cwd, t));
}

function resolveReal(p: string): string {
  try {
    return realpathSync(p);
  } catch {
    return p;
  }
}

export function absoluteForm(rule: string, cwd: string, home: string): string {
  const t = expandHomeInText(rule.trim(), home);
  return path.normalize(path.resolve(cwd, t));
}

function stillHasHomeToken(s: string): boolean {
  return (
    /\$\{HOME\}/.test(s) ||
    /\$HOME\b/.test(s) ||
    /(^|[^A-Za-z0-9_])~(?=\/|$|[^A-Za-z0-9_/])/.test(s)
  );
}

export function expandRuleValues(
  value: string,
  kind: "command" | "path",
  home: string,
  cwd: string,
): string[] {
  const out = new Set<string>();
  out.add(value);
  const expanded = expandHomeInText(value, home);
  out.add(expanded);
  if (kind === "path" && !stillHasHomeToken(expanded)) {
    out.add(absoluteForm(expanded, cwd, home));
  }
  return [...out];
}

export function pathRuleMatchesFull(
  candidate: string,
  ruleValue: string,
  cwd: string,
  home: string,
): boolean {
  const C = normPath(candidate, cwd, home);
  const R = absoluteForm(ruleValue, cwd, home);
  const re = R.includes("*")
    ? new RegExp(`^${globToRegExpSource(R)}$`)
    : undefined;
  if (re ? re.test(C) : C === R) return true;

  const realC = resolveReal(C);
  if (realC !== C && (re ? re.test(realC) : realC === R)) return true;
  if (!re) {
    const realR = resolveReal(R);
    if (realR !== R && (C === realR || realC === realR)) return true;
  }
  return false;
}

function pathMatchesCommandArgv(
  argvs: string[][],
  ruleValue: string,
  cwd: string,
  home: string,
): boolean {
  for (const argv of argvs) {
    for (const token of argv) {
      if (token.startsWith("-")) continue;
      if (
        token.includes("/") ||
        token === ".env" ||
        token.startsWith(".env.")
      ) {
        if (pathRuleMatchesFull(token, ruleValue, cwd, home)) return true;
      }
    }
  }
  return false;
}

function oneLineBody(text: string): string {
  return text.split(/\r\n|\r|\n/).join(" ").trim();
}

export function resolveBlockReason(
  rule: Rule,
  kind: "command" | "path",
  defaultReason?: string,
): string {
  const ruleReason =
    rule.reason !== undefined && rule.reason !== ""
      ? oneLineBody(rule.reason)
      : undefined;
  const isUserRule = rule.source === "user";
  const header = isUserRule
    ? "BY USER"
    : kind === "command"
      ? "COMMAND"
      : "PATH";
  const targetKey = kind === "command" ? "command" : "path";
  const targetLine = `${targetKey}: ${rule.value}`;
  let detail = ruleReason;
  if (
    detail === undefined &&
    isUserRule &&
    defaultReason !== undefined &&
    defaultReason !== ""
  ) {
    detail = oneLineBody(defaultReason);
  }
  if (detail !== undefined) {
    return `! FORBIDDEN ${header}\n${targetLine}\nreason: ${detail}`;
  }
  return `! FORBIDDEN ${header}\n${targetLine}`;
}

// ============================================================================
// OMP Hashline Edit 深度路径抽取 (Hashline Edit Path Extraction)
// ============================================================================

export function extractEditPaths(input: string): string[] {
  const paths = new Set<string>();
  const headerRe = /^\s*\[([^\]\r\n#]+)(?:#[0-9a-fA-F]{4})?\]/gm;
  let m: RegExpExecArray | null;
  while ((m = headerRe.exec(input)) !== null) {
    if (m[1]?.trim()) {
      paths.add(m[1].trim());
    }
  }
  const mvRe = /^\s*MV\s+(?:"([^"\r\n]+)"|'([^'\r\n]+)'|(\S+))/gm;
  while ((m = mvRe.exec(input)) !== null) {
    const dest = m[1] || m[2] || m[3];
    if (dest?.trim()) {
      paths.add(dest.trim());
    }
  }
  return [...paths];
}

// ============================================================================
// 防护评估主引擎 (Guard Evaluation Engine)
// ============================================================================

export function evaluateGuard(input: GuardInput, policy: Policy): GuardResult {
  if (input.tool === "bash") {
    const command = expandHomeInText(input.command, input.home);
    const argvs = simpleCommandArgvs(tokenizeShell(command));
    for (const rule of policy.commands) {
      if (commandMatchesPattern(command, rule.value)) {
        return {
          block: true,
          reason: resolveBlockReason(rule, "command", policy.default_reason),
        };
      }
    }
    for (const rule of policy.paths) {
      if (
        pathMatchesCommandArgv(
          argvs,
          rule.value,
          input.cwd,
          input.home,
        )
      ) {
        return {
          block: true,
          reason: resolveBlockReason(rule, "path", policy.default_reason),
        };
      }
    }
    for (const script of embeddedScripts(argvs, command)) {
      const inner = evaluateGuard(
        { tool: "bash", command: script, cwd: input.cwd, home: input.home },
        policy,
      );
      if (inner.block) return inner;
    }
    return { block: false };
  }

  // 收集并分解跨工具候选路径（自动按分号拆分 grep/glob 多目标路径）
  const candidateList = new Set<string>();

  const addPathToken = (raw: string) => {
    if (raw.includes(";")) {
      for (const seg of raw.split(";")) {
        if (seg.trim() !== "") candidateList.add(seg.trim());
      }
    } else if (raw.trim() !== "") {
      candidateList.add(raw.trim());
    }
  };

  if (typeof input.path === "string") {
    addPathToken(input.path);
  }

  if (Array.isArray(input.paths)) {
    for (const p of input.paths) {
      if (typeof p === "string") {
        addPathToken(p);
      }
    }
  }

  if (typeof input.input === "string" && input.input.trim() !== "") {
    for (const p of extractEditPaths(input.input)) {
      addPathToken(p);
    }
  }

  if (candidateList.size === 0) {
    return { block: false };
  }

  for (const rawCandidate of candidateList) {
    const pathValue = expandHomeInText(rawCandidate, input.home);
    const candidateVariants = [pathValue];
    const stripped = stripOmpSelector(pathValue);
    if (stripped !== pathValue && stripped.trim() !== "") {
      candidateVariants.push(stripped.trim());
    }

    for (const variant of candidateVariants) {
      for (const rule of policy.paths) {
        if (
          pathRuleMatchesFull(variant, rule.value, input.cwd, input.home)
        ) {
          return {
            block: true,
            reason: resolveBlockReason(rule, "path", policy.default_reason),
          };
        }
      }
    }
  }

  return { block: false };
}

// ============================================================================
// 声明式多层 YAML 策略合并引擎 (Multi-Tier YAML Policy Merging)
// ============================================================================

function isRemoveString(raw: string): string | null {
  const t = raw.trim();
  if (t.startsWith("-") && !t.startsWith("--") && t.length > 1) {
    return t.slice(1);
  }
  return null;
}

function isNonEmptyString(v: unknown): v is string {
  return typeof v === "string" && v.trim() !== "";
}

function parseListOps(
  list: unknown,
  valueKey: "pattern" | "path",
): { ops: LayerOp[]; errors: string[] } {
  if (list == null) return { ops: [], errors: [] };
  if (!Array.isArray(list)) return { ops: [], errors: ["配置项必须为列表数组"] };

  const ops: LayerOp[] = [];
  const errors: string[] = [];

  for (let idx = 0; idx < list.length; idx++) {
    const item = list[idx];
    if (isNonEmptyString(item)) {
      const remove = isRemoveString(item);
      if (remove !== null) {
        ops.push({ type: "remove", value: remove });
        continue;
      }
      ops.push({ type: "add", value: item.trim() });
      continue;
    }

    if (item && !Array.isArray(item) && typeof item === "object") {
      const obj = item as Record<string, unknown>;
      const value = isNonEmptyString(obj[valueKey])
        ? obj[valueKey]
        : undefined;
      if (value === undefined) {
        errors.push(`第 ${idx + 1} 项缺少必要的 '${valueKey}' 属性`);
        continue;
      }
      const reason = isNonEmptyString(obj.reason) ? obj.reason : undefined;
      ops.push(
        reason === undefined
          ? { type: "add", value }
          : { type: "add", value, reason },
      );
      continue;
    }

    errors.push(`第 ${idx + 1} 项格式无效`);
  }

  return { ops, errors };
}

type FallbackYamlDoc = {
  default_reason?: string;
  deny_commands: Array<string | Record<string, string>>;
  deny_paths: Array<string | Record<string, string>>;
};

/** 纯正则轻量级 fallback 解析器（仅在宿主环境完全无 YAML 解析器时启用） */
export function parseSimpleYamlFallback(source: string): FallbackYamlDoc {
  const result: FallbackYamlDoc = {
    deny_commands: [],
    deny_paths: [],
  };
  const lines = source.split(/\r?\n/);
  let currentKey: "deny_commands" | "deny_paths" | null = null;
  let currentItem: Record<string, string> | null = null;

  for (let line of lines) {
    const commentIdx = line.indexOf("#");
    if (commentIdx !== -1) line = line.slice(0, commentIdx);
    const trimmed = line.trim();
    if (!trimmed) continue;

    if (trimmed.startsWith("default_reason:")) {
      const val = trimmed.slice("default_reason:".length).trim();
      result.default_reason = val.replace(/^["']|["']$/g, "");
      currentKey = null;
      currentItem = null;
      continue;
    }

    if (trimmed.startsWith("deny_commands:")) {
      currentKey = "deny_commands";
      currentItem = null;
      continue;
    }

    if (trimmed.startsWith("deny_paths:")) {
      currentKey = "deny_paths";
      currentItem = null;
      continue;
    }

    if (currentKey && trimmed.startsWith("-")) {
      const val = trimmed.slice(1).trim();
      if (!val) {
        currentItem = {};
        result[currentKey].push(currentItem);
      } else if (val.includes(":")) {
        const colon = val.indexOf(":");
        const k = val.slice(0, colon).trim();
        const v = val
          .slice(colon + 1)
          .trim()
          .replace(/^["']|["']$/g, "");
        currentItem = { [k]: v };
        result[currentKey].push(currentItem);
      } else {
        currentItem = null;
        result[currentKey].push(val.replace(/^["']|["']$/g, ""));
      }
      continue;
    }

    if (currentKey && currentItem && trimmed.includes(":")) {
      const colon = trimmed.indexOf(":");
      const k = trimmed.slice(0, colon).trim();
      const v = trimmed
        .slice(colon + 1)
        .trim()
        .replace(/^["']|["']$/g, "");
      currentItem[k] = v;
    }
  }

  return result;
}

export function parseLayerYaml(source: string): ParseLayerResult {
  let doc: unknown;
  const bunGlobal = (globalThis as unknown as {
    Bun?: { YAML?: { parse: (s: string) => unknown } };
  }).Bun;

  // 严谨 fail-fast：优先使用 Bun.YAML；若语法错误直接报错抛出，绝不静默降级掩盖配置错误
  if (typeof bunGlobal?.YAML?.parse === "function") {
    try {
      doc = bunGlobal.YAML.parse(source);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      return { ok: false, error: msg };
    }
  } else {
    try {
      doc = parseSimpleYamlFallback(source);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      return { ok: false, error: msg };
    }
  }

  if (doc == null) {
    return {
      ok: true,
      layer: { commandOps: [], pathOps: [], errors: [] },
    };
  }

  if (!(doc instanceof Object) || Array.isArray(doc)) {
    return { ok: false, error: "YAML 根节点必须为映射字典" };
  }

  const root = doc as Record<string, unknown>;
  const commands = parseListOps(root.deny_commands, "pattern");
  const paths = parseListOps(root.deny_paths, "path");

  const layer: ParsedLayer = {
    commandOps: commands.ops,
    pathOps: paths.ops,
    errors: [...commands.errors, ...paths.errors],
  };

  const dr = root.default_reason;
  if (isNonEmptyString(dr)) {
    layer.default_reason = dr;
  }

  return { ok: true, layer };
}

export type ExpandCtx = { home: string; cwd: string };

function materializeRules(
  rules: Rule[],
  kind: "command" | "path",
  ctx: ExpandCtx,
): Rule[] {
  const out: Rule[] = [];
  const seen = new Set<string>();
  for (const rule of rules) {
    for (const value of expandRuleValues(
      rule.value,
      kind,
      ctx.home,
      ctx.cwd,
    )) {
      if (seen.has(value)) continue;
      seen.add(value);
      out.push(
        rule.reason === undefined
          ? { value, source: rule.source }
          : { value, reason: rule.reason, source: rule.source },
      );
    }
  }
  return out;
}

export function applyOps(
  rules: Rule[],
  ops: LayerOp[],
  kind: "command" | "path",
  ctx: ExpandCtx,
): Rule[] {
  let out = rules.slice();
  for (const op of ops) {
    if (op.type === "remove") {
      const drop = new Set(
        expandRuleValues(op.value, kind, ctx.home, ctx.cwd),
      );
      out = out.filter((r) => !drop.has(r.value));
      continue;
    }
    for (const value of expandRuleValues(
      op.value,
      kind,
      ctx.home,
      ctx.cwd,
    )) {
      const next: Rule =
        op.reason === undefined
          ? { value, source: "user" }
          : { value, reason: op.reason, source: "user" };
      const i = out.findIndex((r) => r.value === value);
      if (i >= 0) out[i] = next;
      else out.push(next);
    }
  }
  return out;
}

export function buildPolicy(input: {
  globalSource?: string | null;
  projectSource?: string | null;
  home?: string;
  cwd?: string;
}): BuildPolicyResult {
  const errors: string[] = [];
  const ctx: ExpandCtx = {
    home: input.home ?? "",
    cwd: input.cwd ?? ".",
  };
  let commands = materializeRules(BUILTIN_COMMANDS, "command", ctx);
  let paths = materializeRules(BUILTIN_PATHS, "path", ctx);
  let default_reason: string | undefined;

  const layers: Array<{ name: string; source: string | null | undefined }> = [
    { name: "全局配置", source: input.globalSource },
    { name: "项目配置", source: input.projectSource },
  ];

  for (const { name, source } of layers) {
    if (source == null) continue;

    const parsed = parseLayerYaml(source);
    if (!parsed.ok) {
      errors.push(`${name}: ${parsed.error}`);
      continue;
    }

    for (const err of parsed.layer.errors) {
      errors.push(`${name}: ${err}`);
    }

    if (parsed.layer.default_reason !== undefined) {
      default_reason = parsed.layer.default_reason;
    }
    commands = applyOps(commands, parsed.layer.commandOps, "command", ctx);
    paths = applyOps(paths, parsed.layer.pathOps, "path", ctx);
  }

  const policy: Policy =
    default_reason === undefined
      ? { commands, paths }
      : { default_reason, commands, paths };

  return { policy, errors };
}

function resolveFirstExisting(candidates: string[]): string {
  for (const candidate of candidates) {
    if (existsSync(candidate)) return candidate;
  }
  return candidates[0];
}

export function getPermissionPaths(
  cwd: string,
  agentDir?: string,
): PermissionPaths {
  const home = homedir();
  const fallbackAgentDir =
    agentDir ||
    process.env.OMP_AGENT_DIR ||
    path.join(home, ".omp/agent");

  const globalPath = resolveFirstExisting([
    path.join(fallbackAgentDir, "permissions.yml"),
    path.join(fallbackAgentDir, "permissions.yaml"),
  ]);

  const projectPath = resolveFirstExisting([
    path.join(cwd, ".omp", "permissions.yml"),
    path.join(cwd, ".omp", "permissions.yaml"),
  ]);

  return { globalPath, projectPath };
}

export function readConfigFile(filePath: string): ReadConfigResult {
  try {
    return { status: "ok", text: readFileSync(filePath, "utf8") };
  } catch (e) {
    const err = e as NodeJS.ErrnoException;
    if (err?.code === "ENOENT") {
      return { status: "missing" };
    }
    return {
      status: "error",
      message: e instanceof Error ? e.message : String(e),
    };
  }
}

function sourceFromRead(
  filePath: string,
  read: ReadConfigResult,
  failures: LoadFailure[],
): string | null {
  if (read.status === "ok") return read.text;
  if (read.status === "error") {
    failures.push({ path: filePath, message: read.message });
  }
  return null;
}

export function loadPolicyFromPaths(
  paths: PermissionPaths,
  readers?: {
    readGlobal?: () => ReadConfigResult;
    readProject?: () => ReadConfigResult;
  },
  expand?: { home?: string; cwd?: string },
): LoadPolicyResult {
  const failures: LoadFailure[] = [];
  const globalRead = readers?.readGlobal
    ? readers.readGlobal()
    : readConfigFile(paths.globalPath);
  const projectRead = readers?.readProject
    ? readers.readProject()
    : readConfigFile(paths.projectPath);

  const globalSource = sourceFromRead(paths.globalPath, globalRead, failures);
  const projectSource = sourceFromRead(
    paths.projectPath,
    projectRead,
    failures,
  );

  const built = buildPolicy({
    globalSource,
    projectSource,
    home: expand?.home,
    cwd: expand?.cwd,
  });

  for (const err of built.errors) {
    if (err.startsWith("全局配置:")) {
      failures.push({
        path: paths.globalPath,
        message: err.slice("全局配置:".length).trim(),
      });
    } else if (err.startsWith("项目配置:")) {
      failures.push({
        path: paths.projectPath,
        message: err.slice("项目配置:".length).trim(),
      });
    } else {
      failures.push({ path: paths.globalPath, message: err });
    }
  }

  return { policy: built.policy, failures };
}

// ============================================================================
// OMP 扩展生命周期入口 (OMP Extension Entry Point)
// ============================================================================

export default function ompGuard(pi: ExtensionAPI): void {
  // 按 CWD 独立缓存策略，确保在不同目录切换执行工具时动态生效对应目录的 permissions.yml
  const policyCache = new Map<string, Policy>();
  const notifiedPaths = new Set<string>();

  function reportFailures(ctx: ExtensionContext, failures: LoadFailure[]): void {
    for (const failure of failures) {
      const msg = `omp-guard: 无法加载配置 ${failure.path}: ${failure.message}；该层已忽略（fail-open）`;
      console.error(msg);
      if (notifiedPaths.has(failure.path)) continue;
      notifiedPaths.add(failure.path);
      if (ctx.hasUI && ctx.ui?.notify) {
        ctx.ui.notify(msg, "error");
      }
    }
  }

  function ensurePolicy(ctx: ExtensionContext): Policy {
    const cwd = ctx.cwd;
    const cached = policyCache.get(cwd);
    if (cached) return cached;

    const paths = getPermissionPaths(cwd);
    const loaded = loadPolicyFromPaths(paths, undefined, {
      home: homedir(),
      cwd,
    });
    policyCache.set(cwd, loaded.policy);
    reportFailures(ctx, loaded.failures);
    return loaded.policy;
  }

  function resetPolicy(): void {
    policyCache.clear();
    notifiedPaths.clear();
  }

  pi.on("session_start", (_event, ctx) => {
    resetPolicy();
    ensurePolicy(ctx);
  });

  pi.on("tool_call", async (event: ToolCallEvent, ctx: ExtensionContext) => {
    const active = ensurePolicy(ctx);
    const cwd = ctx.cwd;
    const home = homedir();
    const toolName = event.toolName;
    const input = event.input ?? {};

    if (toolName === "bash") {
      const result = evaluateGuard(
        {
          tool: "bash",
          command: typeof input.command === "string" ? input.command : "",
          cwd,
          home,
        },
        active,
      );
      if (result.block) {
        return { block: true, reason: result.reason };
      }
      return;
    }

    if (toolName === "edit") {
      const result = evaluateGuard(
        {
          tool: "edit",
          path: typeof input.path === "string" ? input.path : undefined,
          input: typeof input.input === "string" ? input.input : undefined,
          cwd,
          home,
        },
        active,
      );
      if (result.block) {
        return { block: true, reason: result.reason };
      }
      return;
    }

    if (toolName === "ast_edit") {
      const result = evaluateGuard(
        {
          tool: "ast_edit",
          paths: Array.isArray(input.paths)
            ? (input.paths as string[])
            : undefined,
          cwd,
          home,
        },
        active,
      );
      if (result.block) {
        return { block: true, reason: result.reason };
      }
      return;
    }

    // 对 read / write / grep / glob 等工具，提取路径并按分号展开检查
    const candidatePaths: string[] = [];
    if (typeof input.path === "string" && input.path.trim() !== "") {
      candidatePaths.push(input.path);
    }
    if (Array.isArray(input.paths)) {
      for (const p of input.paths) {
        if (typeof p === "string" && p.trim() !== "") {
          candidatePaths.push(p);
        }
      }
    }

    if (candidatePaths.length > 0) {
      const result = evaluateGuard(
        {
          tool: toolName,
          paths: candidatePaths,
          cwd,
          home,
        },
        active,
      );
      if (result.block) {
        return { block: true, reason: result.reason };
      }
    }
  });
}
