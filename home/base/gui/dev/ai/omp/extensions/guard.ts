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
 * 7. 声明式 YAML 多层策略继承（内置规则 -> 全局 permissions.yml -> 项目级 permissions.yml，按 CWD 缓存）与 allow_read_paths 确切路径只读授权；
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
  /** 确切路径只读授权：仅放行 read/grep/glob 与纯读取 bash，绝不放行写入 */
  allow_read_paths: Rule[];
};

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
  { value: "rm -rf .", reason: "禁止当前目录整体递归强制删除", source: "builtin" },
  { value: "rm -rf *", reason: "禁止展开范围未确认的活跃通配递归删除", source: "builtin" },
  { value: "rm -rf ./*", reason: "禁止展开范围未确认的活跃通配递归删除", source: "builtin" },
  { value: "rm -rf .*", reason: "禁止展开范围未确认的活跃通配递归删除", source: "builtin" },
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
  /** heredoc 正文；quoted 表示分隔符带引用（正文为纯数据） */
  | { kind: "heredoc"; value: string; quoted: boolean };

/** 单条简单命令节点：保留重定向目标与各词的活跃通配状态 */
type ShellNode = {
  argv: string[];
  activeGlobs: boolean[];
  inTargets: boolean[];
  outTargets: boolean[];
  heredocs: { value: string; quoted: boolean }[];
  pipelineStart: boolean;
  dynamic: boolean;
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

/** 从 openParen（指向 "$(" 的 "("）扫描平衡括号且感知引号/转义的命令替换内容 */
function scanCommandSub(
  input: string,
  openParen: number,
): { body: string; end: number } {
  let depth = 1;
  let i = openParen + 1;
  let body = "";
  while (i < input.length) {
    const c = input[i];
    if (c === "\\") {
      body += c + (input[i + 1] ?? "");
      i += 2;
      continue;
    }
    if (c === "'") {
      const close = input.indexOf("'", i + 1);
      const stop = close === -1 ? input.length : close + 1;
      body += input.slice(i, stop);
      i = stop;
      continue;
    }
    if (c === '"') {
      let j = i + 1;
      while (j < input.length && input[j] !== '"') {
        if (input[j] === "\\") j++;
        j++;
      }
      body += input.slice(i, Math.min(j + 1, input.length));
      i = j + 1;
      continue;
    }
    if (c === "`") {
      let j = i + 1;
      while (j < input.length && input[j] !== "`") {
        if (input[j] === "\\") j++;
        j++;
      }
      body += input.slice(i, Math.min(j + 1, input.length));
      i = j + 1;
      continue;
    }
    if (c === "(") depth++;
    if (c === ")") {
      depth--;
      if (depth === 0) return { body, end: i };
    }
    body += c;
    i++;
  }
  return { body, end: input.length };
}

/** 从 start（指向反引号）扫描到配对反引号 */
function scanBacktick(
  input: string,
  start: number,
): { body: string; end: number } {
  let i = start + 1;
  let body = "";
  while (i < input.length) {
    if (input[i] === "\\" && i + 1 < input.length) {
      body += input[i] + input[i + 1];
      i += 2;
      continue;
    }
    if (input[i] === "`") return { body, end: i };
    body += input[i];
    i++;
  }
  return { body, end: input.length };
}

/** 从正文起点消费 heredoc 直到分隔符行；dash 时容忍行首制表符 */
function heredocBody(
  input: string,
  start: number,
  delim: string,
  dash: boolean,
): { body: string; end: number } {
  let i = start;
  let body = "";
  for (;;) {
    if (i >= input.length) return { body, end: input.length };
    const nl = input.indexOf("\n", i);
    const line = nl === -1 ? input.slice(i) : input.slice(i, nl);
    const key = dash ? line.replace(/^\t+/, "") : line;
    if (key === delim) {
      return { body, end: nl === -1 ? input.length : nl + 1 };
    }
    body += line + "\n";
    if (nl === -1) return { body, end: input.length };
    i = nl + 1;
  }
}

/** 扫描自由文本（如无引用 heredoc 正文）中的 $() 与反引号命令替换 */
function scanSubsInText(text: string): string[] {
  const out: string[] = [];
  let i = 0;
  while (i < text.length) {
    if (text[i] === "\\") {
      i += 2;
      continue;
    }
    if (text[i] === "`") {
      const { body, end } = scanBacktick(text, i);
      if (body.trim() !== "") out.push(body);
      i = Math.min(end + 1, text.length + 1);
      continue;
    }
    if (text[i] === "$" && text[i + 1] === "(") {
      const { body, end } = scanCommandSub(text, i + 1);
      if (body.trim() !== "") out.push(body);
      i = Math.min(end + 1, text.length + 1);
      continue;
    }
    i++;
  }
  return out;
}

/** 将 token 流组装为命令节点：保留重定向目标词并标记管道边界与 heredoc 归属 */
function parseShellNodes(tokens: ShellToken[]): ShellNode[] {
  const nodes: ShellNode[] = [];
  let current: ShellNode | null = null;
  let heredocOwners: ShellNode[] | undefined;
  let nextHeredocOwner = 0;
  let pendingTarget: "in" | "out" | null = null;
  let nextStartsPipeline = true;

  const ensureCurrent = (): ShellNode => {
    if (!current) {
      current = {
        argv: [], activeGlobs: [], inTargets: [], outTargets: [], heredocs: [],
        pipelineStart: nextStartsPipeline, dynamic: false,
      };
      nodes.push(current);
      nextStartsPipeline = false;
    }
    return current;
  };
  const appendWord = (
    value: string,
    activeGlob: boolean,
    target: "plain" | "in" | "out",
    dynamic = false,
  ): void => {
    const node = ensureCurrent();
    node.argv.push(value);
    node.activeGlobs.push(activeGlob);
    node.inTargets.push(target === "in");
    node.outTargets.push(target === "out");
    node.dynamic ||= dynamic;
  };

  for (const t of tokens) {
    if (t.kind === "word") {
      appendWord(t.value, t.activeGlob, pendingTarget ?? "plain", t.dynamic);
      pendingTarget = null;
      continue;
    }
    if (t.kind === "heredoc") {
      const owner = heredocOwners?.[nextHeredocOwner++];
      if (owner) owner.heredocs.push({ value: t.value, quoted: t.quoted });
      continue;
    }
    if (t.kind === "sub") continue;
    if (t.value === "|") {
      current = null;
      pendingTarget = null;
      nextStartsPipeline = false;
      continue;
    }
    if (CONTROL_OPS[t.value]) {
      current = null;
      pendingTarget = null;
      nextStartsPipeline = true;
      continue;
    }
    if (t.value.endsWith("<<-") || (t.value.endsWith("<<") && !t.value.endsWith("<<<"))) {
      pendingTarget = null;
      (heredocOwners ??= []).push(ensureCurrent());
      continue;
    }
    if (t.value.includes("<")) {
      pendingTarget = "in";
      continue;
    }
    if (t.value.includes(">")) {
      pendingTarget = "out";
      continue;
    }
  }
  return nodes;
}

export function tokenizeShell(input: string): ShellToken[] {
  const tokens: ShellToken[] = [];
  let i = 0;
  let pendingHeredocs: Array<{ delim: string; quoted: boolean; dash: boolean }> | undefined;

  const pushSub = (start: number, atParen: boolean): number => {
    const scan = atParen
      ? scanCommandSub(input, start + 1)
      : scanBacktick(input, start);
    if (scan.body.trim() !== "") {
      tokens.push({ kind: "sub", value: scan.body });
    }
    return scan.end + 1;
  };

  while (i < input.length) {
    const ch = input[i];
    if (ch === " " || ch === "\t" || ch === "\r") {
      i++;
      continue;
    }
    if (ch === "\n") {
      if (pendingHeredocs) {
        i++;
        for (const hd of pendingHeredocs) {
          const { body, end } = heredocBody(input, i, hd.delim, hd.dash);
          tokens.push({ kind: "heredoc", value: body, quoted: hd.quoted });
          i = end;
        }
        tokens.push({ kind: "op", value: "\n" });
        pendingHeredocs = undefined;
        continue;
      }
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
    const redir = input.slice(i).match(/^(\d*)(>>|<<-|<<<|<<|<|>)/);
    if (redir) {
      const op = redir[0];
      tokens.push({ kind: "op", value: op });
      i += op.length;
      if (op.endsWith("<<-") || (op.endsWith("<<") && !op.endsWith("<<<"))) {
        // heredoc：读取分隔符词（含引用形式）；分隔符词不是文件操作数，正文延后到行尾消费
        while (i < input.length && (input[i] === " " || input[i] === "\t")) i++;
        let delim = "";
        let quoted = false;
        while (i < input.length && !" \t\r\n".includes(input[i])) {
          const c = input[i];
          if (c === "'" || c === '"') {
            quoted = true;
            const q = c;
            i++;
            while (i < input.length && input[i] !== q) {
              delim += input[i];
              i++;
            }
            if (i < input.length) i++;
            continue;
          }
          if (c === "\\" && i + 1 < input.length) {
            delim += input[i + 1];
            quoted = true;
            i += 2;
            continue;
          }
          if ("|;&()<>".includes(c)) break;
          delim += c;
          i++;
        }
        (pendingHeredocs ??= []).push({ delim, quoted, dash: op.endsWith("<<-") });
      }
      continue;
    }

    let word = "";
    let activeGlob = false;
    let dynamic = false;
    let openBracket: number | undefined;
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
          const d = input[i];
          if (d === "\\" && i + 1 < input.length) {
            word += input[i + 1];
            i += 2;
            continue;
          }
          if (d === "`") {
            dynamic = true;
            i = pushSub(i, false);
            continue;
          }
          if (d === "$" && input[i + 1] === "(") {
            dynamic = true;
            i = pushSub(i, true);
            continue;
          }
          if (d === "$" && /[A-Za-z_0-9{@*?!$-]/.test(input[i + 1] ?? "")) dynamic = true;
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
      if (c === "`") {
        dynamic = true;
        i = pushSub(i, false);
        continue;
      }
      if (c === "$" && input[i + 1] === "(") {
        dynamic = true;
        i = pushSub(i, true);
        continue;
      }
      if (c === "$" && /[A-Za-z_0-9{@*?!$-]/.test(input[i + 1] ?? "")) dynamic = true;
      if (c === "*" || c === "?") activeGlob = true;
      if (c === "[" && openBracket === undefined) openBracket = word.length;
      if (c === "]" && openBracket !== undefined) {
        const first = word[openBracket + 1];
        if (
          word.length > openBracket + 1 &&
          ((first !== "!" && first !== "^") || word.length > openBracket + 2)
        ) {
          activeGlob = true;
          openBracket = undefined;
        }
      }
      word += c;
      i++;
    }
    tokens.push({ kind: "word", value: word, activeGlob, dynamic });
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
  for (const t of tokens) {
    if (t.kind === "op") {
      if (CONTROL_OPS[t.value]) {
        if (current.length > 0) out.push(current);
        current = [];
      }
      // 重定向操作符：跳过操作符自身，后随的目标文件作为路径 token 进入 current argv
      continue;
    }
    if (t.kind !== "word") continue;
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

export function commandMatchesPattern(command: string, pattern: string): boolean {
  return commandNodesMatchPattern(command, pattern, parseShellNodes(tokenizeShell(command)));
}

function commandNodesMatchPattern(
  command: string,
  pattern: string,
  nodes: ShellNode[],
): boolean {
  const patternWords = patternWordsOf(pattern);

  // git add 类规则按 pathspec 结构判定，而非前缀通配
  if (
    patternWords?.length === 3 &&
    patternWords[0] === "git" &&
    patternWords[1] === "add" &&
    ["-A", "--all", ".", "*"].includes(patternWords[2])
  ) {
    return gitAddRuleMatches(nodes);
  }

  // 仅默认下载执行规则采用语义匹配，其他自定义管道禁令保留其声明含义。
  const downloadPattern = /^(curl|wget) \*\| ?\*(?:sh|python)\*$/.exec(pattern);
  if (downloadPattern) {
    return downloadPipeExecutes(nodes)?.downloader === downloadPattern[1];
  }

  if (
    patternWords?.length === 3 &&
    basenames(patternWords[0]) === "rm" &&
    patternWords[1] === "-rf"
  ) {
    const target = patternWords[2];
    return nodes.some((node) =>
      rmScopeMatches(node, /[*?\[]/.test(target) ? undefined : target),
    );
  }

  if (patternWords === null) {
    if (pattern.includes("*")) {
      const flags = /[|;&\n]/.test(pattern) ? "i" : "";
      return new RegExp(globToRegExpSource(pattern), flags).test(command);
    }
    return false;
  }
  for (const argv of nodes.map((n) => n.argv)) {
    if (argvStartsWith(stripWrappers(argv), patternWords)) return true;
  }
  return false;
}

const STDIN_INTERPRETERS: Record<string, true> = {
  sh: true,
  bash: true,
  zsh: true,
  dash: true,
  ash: true,
  ksh: true,
  node: true,
  bun: true,
  deno: true,
  perl: true,
  ruby: true,
  php: true,
  lua: true,
  luajit: true,
};

const DOWNLOADERS: Record<string, true> = { curl: true, wget: true };

/** 版本化 python（python3、python3.12 等）同样视为解释器 */
function isStdinInterpreter(head: string): boolean {
  return STDIN_INTERPRETERS[head] === true || /^python(?:\d+(?:\.\d+)*)?$/.test(head);
}

/** 判断该命令节点是否会把 stdin 当作代码执行（裸解释器或 "-" 输入） */
function executesStdin(argv: string[]): boolean {
  const stripped = stripWrappers(argv);
  if (stripped.length === 0) return false;
  if (!isStdinInterpreter(basenames(stripped[0]))) return false;
  return stripped.slice(1).every((a) => a.startsWith("-"));
}

const JSON_STRING = String.raw`(?:"(?:[^"\\\r\n]|\\[^\r\n])*"|'(?:[^'\\\r\n]|\\[^\r\n])*')`;
const JSON_ACCESS = String.raw`(?:\s*(?:\[\s*(?:${JSON_STRING}|-?\d+)\s*\]|\.\s*get\s*\(\s*${JSON_STRING}\s*\)))*`;
const JSON_STDIN = String.raw`json\s*\.\s*(?:load\s*\(\s*sys\s*\.\s*stdin\s*\)|loads\s*\(\s*sys\s*\.\s*stdin\s*\.\s*read\s*\(\s*\)\s*\))`;
const JSON_DATA = `${JSON_STDIN}${JSON_ACCESS}`;

function jsonStdoutExpression(data: string): string {
  return String.raw`(?:print\s*\(\s*${data}\s*\)|print\s*\(\s*json\s*\.\s*dumps\s*\(\s*${data}\s*\)\s*\)|json\s*\.\s*dump\s*\(\s*${data}\s*,\s*sys\s*\.\s*stdout\s*\))`;
}

// ponytail: 只证明 JSON 读取、索引/get 和 stdout 输出子集；其他脚本拦截，扩展需 Python AST。
const FIXED_JSON_SCRIPT = new RegExp(
  String.raw`^\s*import\s+(?:json\s*,\s*sys|sys\s*,\s*json)\s*;\s*(?:${jsonStdoutExpression(JSON_DATA)}|(?!(?:json|sys|print)\b)([A-Za-z_]\w*)\s*=\s*${JSON_DATA}\s*;\s*${jsonStdoutExpression(String.raw`\1${JSON_ACCESS}`)})\s*;?\s*$`,
);

function fixedScriptExecutesStdin(argv: string[]): boolean {
  const stripped = stripWrappers(argv);
  if (stripped.length === 0) return false;
  const head = basenames(stripped[0]);
  if (!isStdinInterpreter(head)) return false;
  if (!head.startsWith("python")) return true;
  const codeIdx = stripped.findIndex(
    (a, idx) => idx > 0 && (a === "-c" || /^-[a-zA-Z]*c$/.test(a)),
  );
  if (codeIdx === -1 || codeIdx + 1 >= stripped.length) return true;
  if (stripped.slice(1, codeIdx).some((a) => !a.startsWith("-"))) return true;
  return !FIXED_JSON_SCRIPT.test(stripped[codeIdx + 1]);
}

/** 下载命令与解释器位于同一管道且后者消费其输出时，判定为下载即执行 */
function downloadPipeExecutes(
  nodes: ShellNode[],
): { downloader: string; executor: string } | null {
  let downloader = "";
  for (const node of nodes) {
    if (node.pipelineStart) downloader = "";
    const stripped = stripWrappers(node.argv);
    if (stripped.length === 0) continue;
    const head = basenames(stripped[0]).toLowerCase();
    if (downloader === "") {
      if (DOWNLOADERS[head] === true) downloader = head;
      continue;
    }
    if (executesStdin(node.argv) || fixedScriptExecutesStdin(node.argv)) {
      return { downloader, executor: head };
    }
  }
  return null;
}

/** 收集 git add 的显式 pathspec（-- 之后的参数全部视为 pathspec） */
const GIT_GLOBAL_VALUE_OPTIONS: Record<string, true> = {
  "-C": true, "-c": true, "--git-dir": true, "--work-tree": true,
  "--namespace": true, "--config-env": true, "--super-prefix": true,
};

function gitAddScope(argv: string[]): {
  pathspecs: string[]; fromFile: boolean; previewOrInteractive: boolean;
} | null {
  const stripped = stripWrappers(argv);
  if (stripped.length < 2 || basenames(stripped[0]) !== "git") return null;
  let idx = 1;
  while (idx < stripped.length && stripped[idx].startsWith("-")) {
    idx += GIT_GLOBAL_VALUE_OPTIONS[stripped[idx]] === true ? 2 : 1;
  }
  if (stripped[idx] !== "add") return null;
  const pathspecs: string[] = [];
  let fromFile = false;
  let previewOrInteractive = false;
  let afterSeparator = false;
  for (let j = idx + 1; j < stripped.length; j++) {
    const a = stripped[j];
    if (afterSeparator) {
      pathspecs.push(a);
      continue;
    }
    if (a === "--") {
      afterSeparator = true;
      continue;
    }
    if (a === "--pathspec-from-file" || a.startsWith("--pathspec-from-file=")) fromFile = true;
    previewOrInteractive ||= a === "--dry-run" || a === "--patch" ||
      a === "--interactive" || /^-[a-zA-Z]*[npi][a-zA-Z]*$/.test(a);
    if (a.startsWith("-")) continue;
    pathspecs.push(a);
  }
  return { pathspecs, fromFile, previewOrInteractive };
}

/** 全量/通配类 pathspec：.、..、:/、:(top...)、活跃 glob 与 stdin 占位 */
function isFullScopePathspec(p: string): boolean {
  return (
    p === "." ||
    p === ".." ||
    p === ":/" ||
    p === "-" ||
    p.startsWith(":(top") ||
    /[*?\[]/.test(p)
  );
}

/** git add 类规则：非交互、非预览的全量暂存或无法确认的间接范围命中 */
function gitAddRuleMatches(nodes: ShellNode[]): boolean {
  for (const node of nodes) {
    const scope = gitAddScope(node.argv);
    if (!scope) continue;
    if (
      scope.fromFile ||
      (!scope.previewOrInteractive && (
        scope.pathspecs.length === 0 ||
        scope.pathspecs.some(isFullScopePathspec)
      ))
    ) {
      return true;
    }
  }
  return false;
}

/** 在真正的 rm 操作数上检查范围，重定向目标不属于删除操作数 */
function rmScopeMatches(node: ShellNode, protectedTarget?: string): boolean {
  const stripped = stripWrappers(node.argv);
  if (stripped.length === 0 || basenames(stripped[0]) !== "rm") return false;
  const offset = node.argv.length - stripped.length;
  let hasR = false;
  let hasF = false;
  let afterSeparator = false;
  let targetMatches = protectedTarget === undefined && node.dynamic;
  for (let j = 1; j < stripped.length; j++) {
    if (node.inTargets[offset + j] || node.outTargets[offset + j]) continue;
    const a = stripped[j];
    if (!afterSeparator && a === "--") {
      afterSeparator = true;
      continue;
    }
    if (!afterSeparator && a.startsWith("-") && a.length > 1) {
      if (a === "--recursive") hasR = true;
      else if (a === "--force") hasF = true;
      else if (!a.startsWith("--")) {
        for (const c of a.slice(1)) {
          if (c === "r" || c === "R") hasR = true;
          if (c === "f") hasF = true;
        }
      }
      continue;
    }
    targetMatches ||= protectedTarget === undefined
      ? node.activeGlobs[offset + j] === true
      : path.posix.normalize(a) === path.posix.normalize(protectedTarget);
  }
  return hasR && hasF && targetMatches;
}

/** 提取嵌套在 shell wrapper（如 sh -c, bash -lc, eval）中的内嵌脚本；命令替换由词法器捕获为 sub token */
function embeddedScripts(argvs: string[][]): string[] {
  const scripts: string[] = [];
  const shells: Record<string, true> = {
    sh: true,
    bash: true,
    dash: true,
    zsh: true,
    ash: true,
  };
  for (const argv of argvs) {
    const stripped = stripWrappers(argv);
    if (stripped.length === 0) continue;
    const head = basenames(stripped[0]);
    if (shells[head] === true) {
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

/** 收集命令节点中命中机密路径规则的全部 (node, index) 位置 */
function pathHitsInNodes(
  nodes: ShellNode[],
  ruleValue: string,
  cwd: string,
  home: string,
): Array<{ node: ShellNode; index: number }> {
  const hits: Array<{ node: ShellNode; index: number }> = [];
  for (const node of nodes) {
    for (let index = 0; index < node.argv.length; index++) {
      const token = node.argv[index];
      if (token.startsWith("-")) continue;
      if (
        token.includes("/") ||
        token === ".env" ||
        token.startsWith(".env.")
      ) {
        if (pathRuleMatchesFull(token, ruleValue, cwd, home)) {
          hits.push({ node, index });
        }
      }
    }
  }
  return hits;
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

/** 只读授权仅支持最直接的读取命令；带管道/写重定向/wrapper/chdir 一律不豁免，不放行 sed/awk 等脚本 */
const READ_ONLY_HEADS: Record<string, true> = {
  cat: true,
  head: true,
  tail: true,
  grep: true,
};

/** bash 命中的机密路径是否可豁免：受限元数据探测 / 字面量回显 / 显式只读授权 */
function bashPathExemptable(
  hit: { node: ShellNode; index: number },
  nodes: ShellNode[],
  policy: Policy,
  cwd: string,
  home: string,
  allowReadExempt: boolean,
): boolean {
  const { node, index } = hit;
  // 重定向目标永远不豁免（写向机密路径必须拦截）
  if (node.inTargets[index] || node.outTargets[index]) return false;
  // 下游可能把回显当作读取参数；活跃 glob 会暴露秘密目录内容。
  if (node.activeGlobs[index] || nodes[nodes.indexOf(node) + 1]?.pipelineStart === false) return false;
  const stripped = stripWrappers(node.argv);
  const head = stripped.length > 0 ? basenames(stripped[0]) : "";

  // 受限元数据：存在性与单文件元数据探测不读取内容
  if (METADATA_PROBE_HEADS[head] === true) return true;
  if (head === "git" && stripped[1] === "check-ignore") return true;
  if (head === "ls") {
    // 仅真实存在的单个普通文件可豁免；目录枚举或无法确认时保守拦截
    try {
      const operands = stripped.slice(1).filter((arg) => !arg.startsWith("-"));
      return operands.length === 1 && lstatSync(normPath(operands[0], cwd, home)).isFile();
    } catch {
      return false;
    }
  }
  // echo/printf 的字面路径参数是回显不是读取（嵌套读取已由命令替换递归检查）
  if (LITERAL_ECHO_HEADS[head] === true) return true;

  // 显式只读授权：整条命令必须为纯读取且无写入副作用
  return (
    allowReadExempt &&
    policy.allow_read_paths.length > 0 &&
    isReadAllowed(node.argv[index], policy, cwd, home) &&
    isPureReadCommand(nodes)
  );
}

/** 只读授权仅适用于单条直接读取命令：无管道、无任何重定向、无 wrapper 前缀 */
function isPureReadCommand(nodes: ShellNode[]): boolean {
  if (nodes.length !== 1 || nodes[0].dynamic || nodes[0].heredocs.length > 0) return false;
  const node = nodes[0];
  if (node.outTargets.some((t) => t) || node.inTargets.some((t) => t)) {
    return false;
  }
  // 不剥 wrapper：sudo/env 等前缀存在即视为非直接读取
  const head = node.argv.length > 0 ? basenames(node.argv[0]) : "";
  return READ_ONLY_HEADS[head] === true;
}

// realpath 只保留终点，逐级检查可避免被禁私钥经 Store 链接丢失保护身份。
function protectedLinkTarget(candidate: string, policy: Policy, cwd: string, home: string): boolean {
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
      return !(typeof error === "object" && error !== null && "code" in error && error.code === "ENOENT");
    }
    if (policy.paths.some((rule) => pathRuleMatchesFull(target, rule.value, cwd, home))) return true;
    current = target;
  }
}

/**
 * 确切路径只读授权判定：仅精确路径（无通配）生效；相对条目只接受其构建期
 * 绝对形态（防止命令换目录后同名文件被当成已授权路径）；授权条目软链接到
 * 被禁目标时该授权永不生效（防私钥绕过）。
 */
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
    if (!path.isAbsolute(rule.value) && !stillHasHomeToken(rule.value)) {
      continue;
    }
    const A = absoluteForm(rule.value, cwd, home);
    const realA = resolveReal(A);
    if (C !== A && realC !== A && C !== realA) continue;
    try {
      if (!lstatSync(realA).isFile()) continue;
    } catch (error) {
      if (!(typeof error === "object" && error !== null && "code" in error && error.code === "ENOENT")) continue;
    }
    if (
      protectedLinkTarget(A, policy, cwd, home) ||
      (C !== A && protectedLinkTarget(C, policy, cwd, home))
    ) continue;
    if (realA === A) {
      // 授权条目本身不是软链接：候选必须解析到同一文件
      if (C === A || realC === realA) return true;
      continue;
    }
    // 授权条目是软链接：真实目标仍被禁则此授权永不生效
    const targetDenied = policy.paths.some((r) =>
      pathRuleMatchesFull(realA, r.value, cwd, home),
    );
    if (!targetDenied) return true;
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

export function evaluateGuard(
  input: GuardInput,
  policy: Policy,
  opts?: { allowReadExempt?: boolean },
): GuardResult {
  // 内嵌脚本（命令替换 / sh -c / eval / 解释器 heredoc）中禁用只读授权豁免，
  // 防止借外层包装把授权扩大到非纯读取上下文
  const allowReadExempt = opts?.allowReadExempt ?? true;
  if ("command" in input) {
    const command = expandHomeInText(input.command, input.home);
    const tokens = tokenizeShell(command);
    const nodes = parseShellNodes(tokens);
    const argvs = nodes.map((n) => n.argv);
    for (const rule of policy.commands) {
      if (commandNodesMatchPattern(command, expandHomeInText(rule.value, input.home), nodes)) {
        return {
          block: true,
          reason: resolveBlockReason(rule, "command", policy.default_reason),
        };
      }
    }
    for (const rule of policy.paths) {
      const hits = pathHitsInNodes(nodes, rule.value, input.cwd, input.home);
      if (hits.length === 0) continue;
      const allExempt = hits.every((hit) =>
        bashPathExemptable(hit, nodes, policy, input.cwd, input.home, allowReadExempt),
      );
      if (allExempt) continue;
      return {
        block: true,
        reason: resolveBlockReason(rule, "path", policy.default_reason),
      };
    }
    for (const node of nodes) {
      for (const hd of node.heredocs) {
        // 无引用 heredoc 的命令替换在展开阶段即执行，无论消费者是谁
        if (!hd.quoted) {
          for (const script of scanSubsInText(hd.value)) {
            const inner = evaluateGuard(
              { tool: "bash", command: script, cwd: input.cwd, home: input.home },
              policy,
              { allowReadExempt: false },
            );
            if (inner.block) return inner;
          }
        }
        // 解释器把 heredoc 正文当作代码执行（shell 按脚本评估；python 等仅保守覆盖常见形态）
        if (executesStdin(node.argv)) {
          const inner = evaluateGuard(
            { tool: "bash", command: hd.value, cwd: input.cwd, home: input.home },
            policy,
            { allowReadExempt: false },
          );
          if (inner.block) return inner;
        }
      }
    }
    for (const t of tokens) {
      if (t.kind !== "sub") continue;
      const inner = evaluateGuard(
        { tool: "bash", command: t.value, cwd: input.cwd, home: input.home },
        policy,
        { allowReadExempt: false },
      );
      if (inner.block) return inner;
    }
    for (const script of embeddedScripts(argvs)) {
      const inner = evaluateGuard(
        { tool: "bash", command: script, cwd: input.cwd, home: input.home },
        policy,
        { allowReadExempt: false },
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

  // read/grep/glob 为纯只读工具；write/edit/ast_edit 等一律不受只读授权影响
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
      const denied = policy.paths.find((rule) =>
        pathRuleMatchesFull(variant, rule.value, input.cwd, input.home),
      );
      if (!denied) continue;
      // 选择器剥离后判定授权，使 :50-200 / :raw 等形式同样命中确切授权路径
      if (
        readOnlyTool &&
        isReadAllowed(stripOmpSelector(variant), policy, input.cwd, input.home)
      ) {
        continue;
      }
      return {
        block: true,
        reason: resolveBlockReason(denied, "path", policy.default_reason),
      };
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
  let currentKey:
    | "deny_commands"
    | "deny_paths"
    | "allow_read_paths"
    | null = null;
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
      layer: {
        commandOps: [],
        pathOps: [],
        allowReadOps: [],
        errors: [],
      },
    };
  }

  if (!(doc instanceof Object) || Array.isArray(doc)) {
    return { ok: false, error: "YAML 根节点必须为映射字典" };
  }

  const root = doc as Record<string, unknown>;
  const commands = parseListOps(root.deny_commands, "pattern");
  const paths = parseListOps(root.deny_paths, "path");
  const allowRead = parseListOps(root.allow_read_paths, "path");

  // 只读授权仅支持确切路径；通配条目报配置错误并丢弃，防止批量放行
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
    const home = homedir();
    const toolName = event.toolName;
    const input = event.input ?? {};
    // 只有 bash 支持 cwd 输入；其他工具不能用未知字段伪装其路径解析目录。
    // 策略仍按会话目录加载，避免其他目录的权限文件削弱防护。
    const cwd =
      toolName === "bash" && typeof input.cwd === "string" && input.cwd !== ""
        ? path.resolve(ctx.cwd, expandHomeInText(input.cwd, home))
        : ctx.cwd;

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
