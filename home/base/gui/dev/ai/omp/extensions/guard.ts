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

import { existsSync, lstatSync, readFileSync, readlinkSync, realpathSync } from "node:fs";
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
  /** 确切路径只读授权：只影响读取，写入与执行一律不放行 */
  allow_read_paths: Rule[];
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
  allowReadOps: LayerOp[];
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
  { value: "rm -rf .", reason: "禁止当前目录递归强制删除", source: "builtin" },
  { value: "rm -rf ..", reason: "禁止上级目录递归强制删除", source: "builtin" },
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
  | { kind: "word"; value: string; activeGlob: boolean; dynamic: boolean }
  | { kind: "op"; value: string }
  /** 活跃命令替换（$() 或反引号）捕获到的内嵌脚本 */
  | { kind: "sub"; value: string }
  /** heredoc 正文；quoted 为真时正文是数据；owner 是所属命令首 token 下标 */
  | { kind: "heredoc"; value: string; quoted: boolean; owner: number };

/** 命令中的单个词：记录通配是否生效、取值是否可静态确定、是否为重定向目标 */
export type ShellWord = {
  value: string;
  glob: boolean;
  dynamic: boolean;
  target: "in" | "out" | null;
};

/** 单条简单命令；pipeNext 表示同管道的下游还有命令 */
export type ShellCmd = {
  words: ShellWord[];
  pipeNext: boolean;
  startToken: number;
};

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

/** 扫描 $() 的平衡括号正文（感知引号与转义），返回正文与结束括号下标 */
function scanCommandSub(
  input: string,
  openParen: number,
): { body: string; end: number } {
  let depth = 1;
  let i = openParen + 1;
  while (i < input.length) {
    const c = input[i];
    if (c === "\\") {
      i += 2;
      continue;
    }
    if (c === "'") {
      const close = input.indexOf("'", i + 1);
      i = close === -1 ? input.length : close + 1;
      continue;
    }
    if (c === '"' || c === "`") {
      const quote = c;
      i++;
      while (i < input.length && input[i] !== quote) {
        if (input[i] === "\\") i++;
        i++;
      }
      i++;
      continue;
    }
    if (c === "(") {
      depth++;
      i++;
      continue;
    }
    if (c === ")") {
      depth--;
      if (depth === 0) return { body: input.slice(openParen + 1, i), end: i };
    }
    i++;
  }
  return { body: input.slice(openParen + 1), end: input.length };
}

/** 扫描反引号命令替换正文 */
function scanBacktick(
  input: string,
  start: number,
): { body: string; end: number } {
  let i = start + 1;
  while (i < input.length) {
    if (input[i] === "\\" && i + 1 < input.length) {
      i += 2;
      continue;
    }
    if (input[i] === "`") return { body: input.slice(start + 1, i), end: i };
    i++;
  }
  return { body: input.slice(start + 1), end: input.length };
}

/** 解析 heredoc 分隔符；分隔符带引用时正文不展开，只是数据 */
function heredocDelimiter(
  input: string,
  start: number,
): { delim: string; quoted: boolean; end: number } {
  let i = start;
  while (i < input.length && (input[i] === " " || input[i] === "\t")) i++;
  let delim = "";
  let quoted = false;
  while (i < input.length && !" \t\n|;&<>".includes(input[i])) {
    const c = input[i];
    if (c === "'" || c === '"') {
      const close = input.indexOf(c, i + 1);
      const stop = close === -1 ? input.length : close;
      delim += input.slice(i + 1, stop);
      quoted = true;
      i = stop + 1;
      continue;
    }
    if (c === "\\") {
      delim += input[i + 1] ?? "";
      quoted = true;
      i += 2;
      continue;
    }
    delim += c;
    i++;
  }
  return { delim, quoted, end: i };
}

/** 消费 heredoc 正文直到分隔符行；<<- 允许分隔符前有制表符 */
function heredocBody(
  input: string,
  start: number,
  delim: string,
  dash: boolean,
): { body: string; end: number } {
  let i = start;
  const lines: string[] = [];
  for (;;) {
    const nl = input.indexOf("\n", i);
    const stop = nl === -1 ? input.length : nl;
    const line = input.slice(i, stop);
    if ((dash ? line.replace(/^\t+/, "") : line) === delim) {
      return {
        body: lines.join("\n"),
        end: nl === -1 ? input.length : nl + 1,
      };
    }
    lines.push(line);
    if (nl === -1) return { body: lines.join("\n"), end: input.length };
    i = nl + 1;
  }
}

/** 未引用的 [ 是否构成可展开字符类；未闭合或空区间按字面量处理 */
function hasGlobClass(input: string, start: number): boolean {
  const close = input.indexOf("]", start + 1);
  if (close === -1) return false;
  const inner = input.slice(start + 1, close);
  return inner !== "" && inner !== "!" && !/[\s|;&<>()]/.test(inner);
}

export function tokenizeShell(input: string): ShellToken[] {
  const tokens: ShellToken[] = [];
  let i = 0;
  let cmdStart = 0;
  let pending: Array<{
    delim: string;
    quoted: boolean;
    dash: boolean;
    owner: number;
  }> = [];

  // heredoc 正文在行尾换行之后才出现，必须在此处消费，避免被当成命令或路径
  const flushHeredocs = () => {
    for (const h of pending) {
      const consumed = heredocBody(input, i, h.delim, h.dash);
      tokens.push({
        kind: "heredoc",
        value: consumed.body,
        quoted: h.quoted,
        owner: h.owner,
      });
      i = consumed.end;
    }
    pending = [];
  };

  while (i < input.length) {
    const ch = input[i];
    if (ch === " " || ch === "\t" || ch === "\r") {
      i++;
      continue;
    }
    if (ch === "\n") {
      tokens.push({ kind: "op", value: "\n" });
      i++;
      flushHeredocs();
      cmdStart = tokens.length;
      continue;
    }
    if (input.startsWith("||", i) || input.startsWith("&&", i)) {
      tokens.push({ kind: "op", value: input.slice(i, i + 2) });
      i += 2;
      cmdStart = tokens.length;
      continue;
    }
    if (ch === "|" || ch === ";" || ch === "&" || ch === "(" || ch === ")") {
      tokens.push({ kind: "op", value: ch });
      i++;
      cmdStart = tokens.length;
      continue;
    }
    // 文件描述符复制（2>&1 等）整体消费，其中的 & 不是命令分隔符
    const fdDup = input.slice(i).match(/^\d*>&(?:\d|-)/);
    if (fdDup) {
      tokens.push({ kind: "op", value: fdDup[0] });
      i += fdDup[0].length;
      continue;
    }
    const heredocOp = input.slice(i).match(/^(\d*)(<<-|<<|<<<)/);
    if (heredocOp) {
      tokens.push({ kind: "op", value: heredocOp[0] });
      i += heredocOp[0].length;
      if (heredocOp[2] !== "<<<") {
        const delim = heredocDelimiter(input, i);
        pending.push({
          delim: delim.delim,
          quoted: delim.quoted,
          dash: heredocOp[2] === "<<-",
          owner: cmdStart,
        });
        i = delim.end;
      }
      continue;
    }
    const redir = input.slice(i).match(/^(\d*)(>>|<|>)/);
    if (redir) {
      tokens.push({ kind: "op", value: redir[0] });
      i += redir[0].length;
      continue;
    }

    let word = "";
    let activeGlob = false;
    let dynamic = false;
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

      // 命令替换在单引号之外始终会执行，包括双引号内
      if (c === "$" && input[i + 1] === "(") {
        const sub = scanCommandSub(input, i + 1);
        if (sub.body.trim() !== "") tokens.push({ kind: "sub", value: sub.body });
        dynamic = true;
        i = sub.end + 1;
        continue;
      }
      if (c === "`") {
        const sub = scanBacktick(input, i);
        if (sub.body.trim() !== "") tokens.push({ kind: "sub", value: sub.body });
        dynamic = true;
        i = sub.end + 1;
        continue;
      }
      if (c === "'") {
        i++;
        while (i < input.length && input[i] !== "'") word += input[i++];
        if (i < input.length) i++;
        continue;
      }
      if (c === '"') {
        i++;
        while (i < input.length && input[i] !== '"') {
          const d = input[i];
          if (d === "\\" && i + 1 < input.length) {
            word += input[i + 1];
            i += 2;
            continue;
          }
          if (d === "$" && input[i + 1] === "(") {
            const sub = scanCommandSub(input, i + 1);
            if (sub.body.trim() !== "") {
              tokens.push({ kind: "sub", value: sub.body });
            }
            dynamic = true;
            i = sub.end + 1;
            continue;
          }
          if (d === "`") {
            const sub = scanBacktick(input, i);
            if (sub.body.trim() !== "") {
              tokens.push({ kind: "sub", value: sub.body });
            }
            dynamic = true;
            i = sub.end + 1;
            continue;
          }
          if (d === "$") dynamic = true;
          word += d;
          i++;
        }
        if (i < input.length) i++;
        continue;
      }
      if (c === "\\" && i + 1 < input.length) {
        word += input[i + 1];
        i += 2;
        continue;
      }
      if (c === "$") dynamic = true;
      if (c === "*" || c === "?") activeGlob = true;
      if (c === "[" && hasGlobClass(input, i)) activeGlob = true;
      word += c;
      i++;
    }
    tokens.push({ kind: "word", value: word, activeGlob, dynamic });
  }
  flushHeredocs();
  return tokens;
}

/**
 * 将 Token 拆分为独立命令。
 * 注意：重定向操作符（如 <, >, >>）后的文件名必须保留在当前 argv 中，
 * 保证路径匹配引擎能捕获 `cat < .env` 等重定向注入操作。
 */
export function commandNodes(tokens: ShellToken[]): ShellCmd[] {
  const out: ShellCmd[] = [];
  let words: ShellWord[] = [];
  let startToken = 0;
  let pendingTarget: "in" | "out" | null = null;

  const flush = (pipeNext: boolean) => {
    if (words.length > 0) out.push({ words, pipeNext, startToken });
    words = [];
    pendingTarget = null;
  };

  for (let idx = 0; idx < tokens.length; idx++) {
    const t = tokens[idx];
    if (t.kind === "word") {
      if (words.length === 0) startToken = idx;
      words.push({
        value: t.value,
        glob: t.activeGlob,
        dynamic: t.dynamic,
        target: pendingTarget,
      });
      pendingTarget = null;
      continue;
    }
    if (t.kind !== "op") continue;
    if (t.value === "|") {
      flush(true);
      continue;
    }
    if (CONTROL_OPS[t.value]) {
      flush(false);
      continue;
    }
    pendingTarget = t.value.includes(">") ? "out" : "in";
  }
  flush(false);
  return out;
}

export function simpleCommandArgvs(tokens: ShellToken[]): string[][] {
  return commandNodes(tokens).map((c) => c.words.map((w) => w.value));
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

    // 严格等于真：避免继承属性（constructor 等）被当成受信任包装器
    if (FLAG_WRAPPERS[head] === true) {
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

/** 剥离包装器前缀，同时保留每个词的引用/目标元数据 */
function stripWrapperWords(words: ShellWord[]): ShellWord[] {
  const kept = stripWrappers(words.map((w) => w.value)).length;
  return kept === words.length ? words : words.slice(words.length - kept);
}

function argvStartsWith(words: ShellWord[], patternWords: string[]): boolean {
  const argv = words.map((w) => w.value);
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
  // 只有真实删除目标含有未引用的通配符或动态展开时才命中，
  // 避免把「定向删除字面文件名」（如 rm -rf './build/[draft]'）误判为全量清空。
  const isRmForceGlobPattern =
    head === "rm" &&
    normArgv[1] === "-rf" &&
    patternWords[1] === "-rf" &&
    patternWords.slice(2).some((w) => /[*?\[]/.test(w));
  if (isRmForceGlobPattern) {
    return words
      .slice(2)
      .some((w) => !w.value.startsWith("-") && (w.glob || w.dynamic));
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

/** Git 全局选项；其中带独立取值的选项需要连同后一个词一起跳过 */
const GIT_GLOBAL_VALUE_OPTIONS: Record<string, true> = {
  "-C": true,
  "-c": true,
  "--git-dir": true,
  "--work-tree": true,
  "--namespace": true,
  "--config-env": true,
  "--super-prefix": true,
};

/** 交互式选取与预览不会整体写入暂存区 */
function isGitAddPreviewFlag(arg: string): boolean {
  if (arg.startsWith("--")) {
    return arg === "--patch" || arg === "--interactive" || arg === "--dry-run";
  }
  return /^-[a-zA-Z]*[pin]/.test(arg);
}

/** git add 是否属于「没有明确文件范围」的暂存；排除项不算正向选择 */
function gitAddIsFullScope(argv: string[]): boolean {
  const stripped = stripWrappers(argv);
  if (stripped.length < 2 || basenames(stripped[0]) !== "git") return false;
  let i = 1;
  while (i < stripped.length && stripped[i].startsWith("-")) {
    i += GIT_GLOBAL_VALUE_OPTIONS[stripped[i]] === true ? 2 : 1;
  }
  if (stripped[i] !== "add") return false;

  const pathspecs: string[] = [];
  let afterSeparator = false;
  let preview = false;
  for (let j = i + 1; j < stripped.length; j++) {
    const arg = stripped[j];
    if (afterSeparator) {
      pathspecs.push(arg);
      continue;
    }
    if (arg === "--") {
      afterSeparator = true;
      continue;
    }
    if (arg.startsWith("-")) {
      // 间接 pathspec 无法静态确认范围，按全量处理
      if (
        arg === "--pathspec-from-file" ||
        arg.startsWith("--pathspec-from-file=")
      ) {
        return true;
      }
      if (isGitAddPreviewFlag(arg)) preview = true;
      continue;
    }
    pathspecs.push(arg);
  }
  if (preview) return false;

  const positive = pathspecs.filter((p) => !/^:\(exclude|^:!|^:\^/.test(p));
  if (positive.length === 0) return true;
  return positive.some(
    (p) =>
      p === "." ||
      p === ".." ||
      p === "./" ||
      p === ":/" ||
      p === ":(top)" ||
      /[*?\[]/.test(p),
  );
}

const DOWNLOADERS: Record<string, true> = { curl: true, wget: true };

const STDIN_SHELLS: Record<string, true> = {
  sh: true,
  bash: true,
  zsh: true,
  dash: true,
  ash: true,
  ksh: true,
};

const STDIN_SCRIPTS: Record<string, true> = {
  node: true,
  bun: true,
  deno: true,
  perl: true,
  ruby: true,
  php: true,
  lua: true,
  luajit: true,
};

/** 版本化 python（python3、python3.12 等）同样视为解释器 */
function isStdinInterpreter(head: string): boolean {
  return (
    STDIN_SHELLS[head] === true ||
    STDIN_SCRIPTS[head] === true ||
    /^python(?:\d+(?:\.\d+)*)?$/.test(head)
  );
}

/** Python 字段访问只支持下标与 .get("字面量")，杜绝任何可执行片段 */
const PY_FIELD = String.raw`(?:\s*\[\s*(?:"(?:[^"\\\r\n]|\\[^\r\n])*"|'(?:[^'\\\r\n]|\\[^\r\n])*'|-?\d+)\s*\]|\s*\.\s*get\s*\(\s*"(?:[^"\\\r\n]|\\[^\r\n])*"\s*\))*`;

/** 仅放行固定的「读取 stdin JSON 并打印字段」脚本，其余 python -c 一律保守拦截 */
const SAFE_JSON_SCRIPT = new RegExp(
  String.raw`^\s*import\s+(?:json\s*,\s*sys|sys\s*,\s*json)\s*;\s*print\s*\(\s*json\s*\.\s*(?:load\s*\(\s*sys\s*\.\s*stdin\s*\)|loads\s*\(\s*sys\s*\.\s*stdin\s*\.\s*read\s*\(\s*\)\s*\))${PY_FIELD}\s*\)\s*;?\s*$`,
);

/** 该解释器命令是否把 stdin 当作程序执行 */
function interpreterExecutesStdin(raw: string[]): boolean {
  const argv = stripWrappers(raw);
  if (argv.length === 0) return false;
  const head = basenames(argv[0]).toLowerCase();
  const rest = argv.slice(1);
  if (head.startsWith("python")) {
    const codeIdx = rest.findIndex(
      (a) => a === "-c" || /^-[a-zA-Z]*c[a-zA-Z]*$/.test(a),
    );
    if (codeIdx !== -1) {
      return (
        codeIdx + 1 >= rest.length || !SAFE_JSON_SCRIPT.test(rest[codeIdx + 1])
      );
    }
    return rest.every((a) => a.startsWith("-"));
  }
  // shell 带 -s 或完全没有脚本操作数时从 stdin 读取程序
  if (STDIN_SHELLS[head] === true) {
    return rest.includes("-s") || rest.every((a) => a.startsWith("-"));
  }
  if (STDIN_SCRIPTS[head] === true) {
    return rest.every((a) => a.startsWith("-"));
  }
  return false;
}

/** 同一管道内下载器之后紧跟消费 stdin 的解释器，才算下载即执行 */
function downloadPipeExecutes(nodes: ShellCmd[]): boolean {
  let downloader = false;
  let piped = false;
  for (const node of nodes) {
    if (!piped) downloader = false;
    const argv = stripWrappers(node.words.map((w) => w.value));
    if (argv.length > 0) {
      if (!downloader) {
        downloader = DOWNLOADERS[basenames(argv[0]).toLowerCase()] === true;
      } else if (interpreterExecutesStdin(argv)) {
        return true;
      }
    }
    piped = node.pipeNext;
  }
  return false;
}

/** 内置下载规则形如 curl|wget ... | <解释器>；自定义的数据处理规则走通用匹配 */
function isDownloadRulePattern(pattern: string): boolean {
  if (!/^\s*(curl|wget)\b/.test(pattern)) return false;
  const last = pattern.trim().split(/[|\s]+/).filter(Boolean).pop() ?? "";
  return isStdinInterpreter(last.replace(/[*?]/g, ""));
}

function matchCommandNodes(
  nodes: ShellCmd[],
  tokens: ShellToken[],
  pattern: string,
): boolean {
  if (isDownloadRulePattern(pattern)) return downloadPipeExecutes(nodes);
  const patternWords = patternWordsOf(pattern);
  if (!patternWords) {
    // 含控制符的自定义规则：对去引用后的命令文本做通配匹配，heredoc 正文不参与
    if (!pattern.includes("*")) return false;
    const text = tokens
      .filter((t) => t.kind !== "heredoc")
      .map((t) => t.value)
      .join(" ");
    return new RegExp(globToRegExpSource(pattern), "i").test(text);
  }
  if (patternWords[0] === "git" && patternWords[1] === "add") {
    return nodes.some((c) => gitAddIsFullScope(c.words.map((w) => w.value)));
  }
  return nodes.some((c) =>
    argvStartsWith(stripWrapperWords(c.words), patternWords),
  );
}

export function commandMatchesPattern(
  command: string,
  pattern: string,
): boolean {
  const tokens = tokenizeShell(command);
  return matchCommandNodes(commandNodes(tokens), tokens, pattern);
}

/** 提取嵌套在 shell wrapper（如 sh -c, bash -lc, eval）中的内嵌脚本；命令替换由词法层产出 sub token */
function embeddedScripts(argvs: string[][]): string[] {
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

const METADATA_PROBE_HEADS: Record<string, true> = {
  stat: true,
  test: true,
  "[": true,
  "[[": true,
};

const LITERAL_ECHO_HEADS: Record<string, true> = {
  echo: true,
  printf: true,
};

/** 只读授权只支持最直接的读取命令 */
const READ_ONLY_HEADS: Record<string, true> = {
  cat: true,
  head: true,
  tail: true,
  grep: true,
};

/** 路径不存在按未命中处理，其余错误保持保守 */
function isMissingPathError(error: unknown): boolean {
  return (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    error.code === "ENOENT"
  );
}

/** 逐跳解析软链接：任一跳命中 deny 规则即受保护，被禁目标不能经授权链接绕开 */
function protectedLinkTarget(
  candidate: string,
  policy: Policy,
  cwd: string,
  home: string,
): boolean {
  const seen = new Set<string>();
  let current = candidate;
  for (;;) {
    if (seen.has(current)) return true;
    seen.add(current);
    let target: string;
    try {
      if (!lstatSync(current).isSymbolicLink()) return false;
      target = path.resolve(path.dirname(current), readlinkSync(current));
    } catch (error) {
      return !isMissingPathError(error);
    }
    if (
      policy.paths.some((rule) =>
        pathRuleMatchesFull(target, rule.value, cwd, home),
      )
    ) {
      return true;
    }
    current = target;
  }
}

/** 确切路径只读授权：只认精确路径，授权条目指向被禁目标时永不生效 */
function isReadAllowed(
  candidate: string,
  policy: Policy,
  cwd: string,
  home: string,
): boolean {
  if (policy.allow_read_paths.length === 0) return false;
  const C = normPath(candidate, cwd, home);
  const realC = resolveReal(C);
  for (const rule of policy.allow_read_paths) {
    // 相对条目只接受构建期展开出的绝对形态，避免换目录后同名文件被当作已授权
    if (!path.isAbsolute(rule.value) && !stillHasHomeToken(rule.value)) continue;
    const A = absoluteForm(rule.value, cwd, home);
    if (C !== A && realC !== A) continue;
    try {
      if (!lstatSync(A).isFile()) continue;
    } catch (error) {
      if (!isMissingPathError(error)) continue;
    }
    if (protectedLinkTarget(A, policy, cwd, home)) continue;
    if (C !== A && protectedLinkTarget(C, policy, cwd, home)) continue;
    return true;
  }
  return false;
}

/** 只读授权只适用于单条直接读取命令：无管道、无重定向、无 wrapper、无动态展开 */
function isPureReadCommand(cmd: ShellCmd, soleCommand: boolean): boolean {
  if (!soleCommand || cmd.pipeNext) return false;
  if (cmd.words.some((w) => w.target !== null || w.dynamic)) return false;
  const argv = cmd.words.map((w) => w.value);
  return argv.length > 0 && READ_ONLY_HEADS[basenames(argv[0])] === true;
}

/** 命中机密路径的词是否可豁免：受限元数据探测、字面回显或显式只读授权 */
function bashHitExemptable(
  cmd: ShellCmd,
  wordIdx: number,
  policy: Policy,
  cwd: string,
  home: string,
  allowReadExempt: boolean,
  soleCommand: boolean,
): boolean {
  const word = cmd.words[wordIdx];
  // 写入机密路径、按通配枚举秘密目录一律拦截
  if (word.target !== null || word.glob) return false;
  // 管道下游可能把该值当作读取参数
  if (cmd.pipeNext) return false;

  const argv = cmd.words.map((w) => w.value);
  const stripped = stripWrappers(argv);
  const head = stripped.length > 0 ? basenames(stripped[0]) : "";

  // 受限元数据查询不读取内容
  if (METADATA_PROBE_HEADS[head] === true) return true;
  if (head === "git" && stripped[1] === "check-ignore") return true;
  if (head === "ls") {
    // 只有真实存在的单个普通文件才算元数据查询，目录枚举照旧拦截
    try {
      const operands = stripped.slice(1).filter((a) => !a.startsWith("-"));
      return (
        operands.length === 1 &&
        lstatSync(normPath(operands[0], cwd, home)).isFile()
      );
    } catch {
      return false;
    }
  }
  // echo/printf 的字面路径是回显；其中的命令替换已由 sub token 单独检查
  if (LITERAL_ECHO_HEADS[head] === true) return true;

  return (
    allowReadExempt &&
    isReadAllowed(word.value, policy, cwd, home) &&
    isPureReadCommand(cmd, soleCommand)
  );
}

/** 是否存在无法豁免的机密路径命中 */
function hasBlockingPathHit(
  nodes: ShellCmd[],
  ruleValue: string,
  policy: Policy,
  cwd: string,
  home: string,
  allowReadExempt: boolean,
): boolean {
  const soleCommand = nodes.length === 1;
  return nodes.some((cmd) =>
    cmd.words.some((word, idx) => {
      const token = word.value;
      if (token.startsWith("-")) return false;
      if (
        !(
          token.includes("/") ||
          token === ".env" ||
          token.startsWith(".env.")
        )
      ) {
        return false;
      }
      if (!pathRuleMatchesFull(token, ruleValue, cwd, home)) return false;
      return !bashHitExemptable(
        cmd,
        idx,
        policy,
        cwd,
        home,
        allowReadExempt,
        soleCommand,
      );
    }),
  );
}

/** 扫描自由文本中的命令替换；无引用 heredoc 正文会在展开阶段执行其中的替换 */
function scanSubsInText(text: string): string[] {
  const out: string[] = [];
  let i = 0;
  while (i < text.length) {
    if (text[i] === "\\") {
      i += 2;
      continue;
    }
    if (text[i] === "$" && text[i + 1] === "(") {
      const sub = scanCommandSub(text, i + 1);
      if (sub.body.trim() !== "") out.push(sub.body);
      i = sub.end + 1;
      continue;
    }
    if (text[i] === "`") {
      const sub = scanBacktick(text, i);
      if (sub.body.trim() !== "") out.push(sub.body);
      i = sub.end + 1;
      continue;
    }
    i++;
  }
  return out;
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

export function evaluateGuard(
  input: GuardInput,
  policy: Policy,
  allowReadExempt = true,
): GuardResult {
  if (input.tool === "bash") {
    const command = expandHomeInText(input.command, input.home);
    const tokens = tokenizeShell(command);
    const nodes = commandNodes(tokens);
    const argvs = nodes.map((c) => c.words.map((w) => w.value));

    for (const rule of policy.commands) {
      if (matchCommandNodes(nodes, tokens, rule.value)) {
        return {
          block: true,
          reason: resolveBlockReason(rule, "command", policy.default_reason),
        };
      }
    }
    for (const rule of policy.paths) {
      if (
        hasBlockingPathHit(
          nodes,
          rule.value,
          policy,
          input.cwd,
          input.home,
          allowReadExempt,
        )
      ) {
        return {
          block: true,
          reason: resolveBlockReason(rule, "path", policy.default_reason),
        };
      }
    }

    // 嵌套脚本不再享有只读授权，避免借外层包装扩大授权范围
    const nested = (script: string): GuardResult | undefined => {
      const inner = evaluateGuard(
        { tool: "bash", command: script, cwd: input.cwd, home: input.home },
        policy,
        false,
      );
      return inner.block ? inner : undefined;
    };

    for (const t of tokens) {
      if (t.kind === "sub") {
        const blocked = nested(t.value);
        if (blocked) return blocked;
      }
      if (t.kind === "heredoc") {
        let owner: ShellCmd | undefined;
        for (const cmd of nodes) {
          if (cmd.startToken <= t.owner) owner = cmd;
        }
        const consumed =
          owner !== undefined &&
          interpreterExecutesStdin(owner.words.map((w) => w.value));
        // 解释器把正文当脚本执行；无引用的正文无论消费者是谁都会展开其中的替换
        const body = consumed
          ? t.value
          : t.quoted
            ? ""
            : scanSubsInText(t.value).join("\n");
        if (body !== "") {
          const blocked = nested(body);
          if (blocked) return blocked;
        }
      }
    }

    for (const script of embeddedScripts(argvs)) {
      const blocked = nested(script);
      if (blocked) return blocked;
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

  // read/grep/glob 只做读取；写入类工具不受只读授权影响
  const readOnlyTool =
    input.tool === "read" || input.tool === "grep" || input.tool === "glob";

  for (const rawCandidate of candidateList) {
    const pathValue = expandHomeInText(rawCandidate, input.home);
    const candidateVariants = [pathValue];
    const stripped = stripOmpSelector(pathValue);
    if (stripped !== pathValue && stripped.trim() !== "") {
      candidateVariants.push(stripped.trim());
    }

    for (const variant of candidateVariants) {
      for (const rule of policy.paths) {
        if (!pathRuleMatchesFull(variant, rule.value, input.cwd, input.home)) {
          continue;
        }
        // 选择器（:50-200、:raw 等）剥离后判定授权，确切授权路径才命中
        if (
          readOnlyTool &&
          isReadAllowed(stripOmpSelector(variant), policy, input.cwd, input.home)
        ) {
          continue;
        }
        return {
          block: true,
          reason: resolveBlockReason(rule, "path", policy.default_reason),
        };
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
  allow_read_paths: Array<string | Record<string, string>>;
};

/** 纯正则轻量级 fallback 解析器（仅在宿主环境完全无 YAML 解析器时启用） */
export function parseSimpleYamlFallback(source: string): FallbackYamlDoc {
  const result: FallbackYamlDoc = {
    deny_commands: [],
    deny_paths: [],
    allow_read_paths: [],
  };
  const lines = source.split(/\r?\n/);
  let currentKey: "deny_commands" | "deny_paths" | "allow_read_paths" | null =
    null;
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

    if (trimmed.startsWith("allow_read_paths:")) {
      currentKey = "allow_read_paths";
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
      layer: { commandOps: [], pathOps: [], allowReadOps: [], errors: [] },
    };
  }

  if (!(doc instanceof Object) || Array.isArray(doc)) {
    return { ok: false, error: "YAML 根节点必须为映射字典" };
  }

  const root = doc as Record<string, unknown>;
  const commands = parseListOps(root.deny_commands, "pattern");
  const paths = parseListOps(root.deny_paths, "path");
  const allowRead = parseListOps(root.allow_read_paths, "path");

  // 只读授权必须逐个文件指定；通配条目报配置错误并丢弃，防止批量放行
  const allowReadOps: LayerOp[] = [];
  for (const op of allowRead.ops) {
    if (op.type === "add" && /[*?\[]/.test(op.value)) {
      allowRead.errors.push(
        `allow_read_paths 仅支持确切路径，不支持通配: ${op.value}`,
      );
      continue;
    }
    allowReadOps.push(op);
  }

  const layer: ParsedLayer = {
    commandOps: commands.ops,
    pathOps: paths.ops,
    allowReadOps,
    errors: [...commands.errors, ...paths.errors, ...allowRead.errors],
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
  let allowReadPaths: Rule[] = [];
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
    allowReadPaths = applyOps(
      allowReadPaths,
      parsed.layer.allowReadOps,
      "path",
      ctx,
    );
  }

  const policy: Policy =
    default_reason === undefined
      ? { commands, paths, allow_read_paths: allowReadPaths }
      : { default_reason, commands, paths, allow_read_paths: allowReadPaths };

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
