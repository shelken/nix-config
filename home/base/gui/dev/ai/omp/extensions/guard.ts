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
  | {
      kind: "word";
      value: string;
      activeGlob: boolean;
      dynamic: boolean;
      subs: string[];
    }
  | { kind: "op"; value: string }
  /** 活跃命令替换（$() 或反引号）捕获到的内嵌脚本 */
  | { kind: "sub"; value: string }
  /** heredoc 正文；quoted 仅表示不做替换展开，正文仍可能被解释器当作程序；owner 是所属命令首 token 下标 */
  | { kind: "heredoc"; value: string; quoted: boolean; owner: number };

/** 命令中的单个词：记录通配是否生效、取值是否可静态确定、是否为重定向目标 */
export type ShellWord = {
  value: string;
  glob: boolean;
  dynamic: boolean;
  /** 词内命令替换与进程替换的脚本正文 */
  subs: string[];
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

/** 出现在命令位置时只起语法作用，其后紧跟的才是被执行的命令 */
const RESERVED_WORDS: Record<string, true> = {
  "{": true,
  "}": true,
  "!": true,
  if: true,
  then: true,
  else: true,
  elif: true,
  fi: true,
  while: true,
  until: true,
  do: true,
  done: true,
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

/** 解析 heredoc 分隔符；分隔符带引用时正文仅跳过替换展开，不代表正文是数据 */
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

/** 解码 $'...' 的 ANSI-C 引用；返回正文与结束引号之后的下标 */
function ansiCQuote(
  input: string,
  start: number,
): { text: string; end: number } {
  const simple: Record<string, string> = {
    n: "\n",
    t: "\t",
    r: "\r",
    a: "\x07",
    b: "\b",
    e: "\x1b",
    E: "\x1b",
    f: "\f",
    v: "\v",
  };
  let text = "";
  let i = start;
  while (i < input.length && input[i] !== "'") {
    if (input[i] !== "\\" || i + 1 >= input.length) {
      text += input[i++];
      continue;
    }
    const rest = input.slice(i + 1);
    const code = rest.match(/^(?:x([0-9a-fA-F]{1,2})|([0-7]{1,3}))/);
    if (code) {
      text += String.fromCharCode(
        code[1] !== undefined ? parseInt(code[1], 16) : parseInt(code[2], 8),
      );
      i += 1 + code[0].length;
      continue;
    }
    text += simple[rest[0]] ?? rest[0];
    i += 2;
  }
  return { text, end: i < input.length ? i + 1 : i };
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
    // 注释到行尾为止，其中的文字不会被执行
    if (ch === "#") {
      while (i < input.length && input[i] !== "\n") i++;
      continue;
    }
    // 进程替换 <(cmd) / >(cmd)：正文会被执行，外层命令拿到的是一个文件路径
    if ((ch === "<" || ch === ">") && input[i + 1] === "(") {
      const sub = scanCommandSub(input, i + 1);
      if (sub.body.trim() !== "") tokens.push({ kind: "sub", value: sub.body });
      tokens.push({
        kind: "word",
        value: "/dev/fd/63",
        activeGlob: false,
        dynamic: true,
        subs: [sub.body],
      });
      i = sub.end + 1;
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
    const subs: string[] = [];
    const takeSub = (body: string) => {
      if (body.trim() !== "") {
        tokens.push({ kind: "sub", value: body });
        subs.push(body);
      }
      dynamic = true;
    };
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
        takeSub(sub.body);
        i = sub.end + 1;
        continue;
      }
      if (c === "`") {
        const sub = scanBacktick(input, i);
        takeSub(sub.body);
        i = sub.end + 1;
        continue;
      }
      if (c === "$" && input[i + 1] === "'") {
        const quoted = ansiCQuote(input, i + 2);
        word += quoted.text;
        i = quoted.end;
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
            takeSub(sub.body);
            i = sub.end + 1;
            continue;
          }
          if (d === "`") {
            const sub = scanBacktick(input, i);
            takeSub(sub.body);
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
    tokens.push({ kind: "word", value: word, activeGlob, dynamic, subs });
  }
  flushHeredocs();
  return tokens;
}

/**
 * 将 Token 拆分为独立命令。
 * 注意：重定向操作符（如 <, >, >>）后的文件名必须保留在当前 argv 中，
 * 保证路径匹配引擎能捕获 `cat < .env` 等重定向注入操作。
 * startToken 指向命令段首个 token（含前置重定向），与 heredoc token 的
 * owner 对齐；否则 `2>/tmp/err bash <<EOF` 的正文会因找不到所属命令被当
 * 成无害数据。<< 分隔符与 2>&1 的操作数已被词法层整体消费，其后没有目标词。
 */
export function commandNodes(tokens: ShellToken[]): ShellCmd[] {
  const out: ShellCmd[] = [];
  let words: ShellWord[] = [];
  let startToken = 0;
  let pendingStart: number | null = null;
  let pendingTarget: "in" | "out" | null = null;

  const flush = (pipeNext: boolean) => {
    if (words.length > 0) out.push({ words, pipeNext, startToken });
    words = [];
    pendingStart = null;
    pendingTarget = null;
  };

  for (let idx = 0; idx < tokens.length; idx++) {
    const t = tokens[idx];
    if (t.kind === "word") {
      if (words.length === 0 && RESERVED_WORDS[t.value] === true) {
        // 复合命令的保留字不是命令名，其后的词才是真正的命令头
        if (pendingStart === null) pendingStart = idx;
        continue;
      }
      if (words.length === 0) startToken = pendingStart ?? idx;
      words.push({
        value: t.value,
        glob: t.activeGlob,
        dynamic: t.dynamic,
        subs: t.subs,
        target: pendingTarget,
      });
      pendingTarget = null;
      continue;
    }
    if (t.kind !== "op") {
      // 命令替换 sub token 属于当前命令段的 token 范围，同样计入起点
      if (t.kind === "sub" && words.length === 0 && pendingStart === null) {
        pendingStart = idx;
      }
      continue;
    }
    if (t.value === "|") {
      flush(true);
      continue;
    }
    if (CONTROL_OPS[t.value]) {
      flush(false);
      continue;
    }
    if (words.length === 0 && pendingStart === null) pendingStart = idx;
    if (t.value === "<<" || t.value === "<<-" || /^\d*>&/.test(t.value)) {
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

/** 包装器自身带独立取值的旗标；漏掉会把取值误当成被包装的命令 */
const WRAPPER_VALUE_FLAGS: Record<string, Record<string, true>> = {
  sudo: {
    "-u": true,
    "-g": true,
    "-p": true,
    "-C": true,
    "-D": true,
    "-R": true,
    "-T": true,
    "-U": true,
    "-h": true,
    "-r": true,
    "-t": true,
    "-c": true,
    "--user": true,
    "--group": true,
    "--prompt": true,
    "--chdir": true,
    "--role": true,
    "--type": true,
    "--host": true,
    "--close-from": true,
  },
  doas: { "-u": true, "-C": true },
  timeout: {
    "-k": true,
    "-s": true,
    "--kill-after": true,
    "--signal": true,
  },
  exec: { "-a": true },
  stdbuf: { "-i": true, "-o": true, "-e": true },
  ionice: { "-c": true, "-n": true, "-p": true, "-P": true, "-u": true },
  watch: { "-n": true, "-d": true, "--interval": true },
  xargs: {
    "-I": true,
    "-n": true,
    "-P": true,
    "-s": true,
    "-L": true,
    "-E": true,
    "-a": true,
    "-d": true,
    "-J": true,
  },
  time: { "-f": true, "-o": true },
};

const takesValue = (head: string, flag: string): boolean =>
  WRAPPER_VALUE_FLAGS[head]?.[flag] === true;

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
        if (takesValue(head, f)) {
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
        if (takesValue("timeout", f)) {
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
      while (j < w.length && w[j].startsWith("-")) {
        j += takesValue(head, w[j]) ? 2 : 1;
      }
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
  const operands: string[] = [];
  let afterDashes = false;

  for (let i = 1; i < argv.length; i++) {
    const arg = argv[i];
    if (afterDashes) {
      operands.push(arg);
    } else if (arg === "--") {
      afterDashes = true;
    } else if (arg === "--recursive") {
      hasR = true;
    } else if (arg === "--force") {
      hasF = true;
    } else if (arg.startsWith("--")) {
      // --no-preserve-root、--verbose 等不改变删除目标
    } else if (arg.startsWith("-") && arg.length > 1) {
      for (const ch of arg.slice(1)) {
        if (ch === "r" || ch === "R") hasR = true;
        else if (ch === "f") hasF = true;
      }
    } else {
      operands.push(arg);
    }
  }

  if (hasR && hasF) {
    return [argv[0], "-rf", ...operands];
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

function stripWrapperWords(words: ShellWord[]): ShellWord[] {
  const kept = stripWrappers(words.map((w) => w.value)).length;
  return kept === words.length ? words : words.slice(words.length - kept);
}

/** 重定向目标不是命令操作数；剥离包装器前缀后返回剩余词 */
function operandWords(words: ShellWord[]): ShellWord[] {
  return stripWrapperWords(words.filter((w) => w.target === null));
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

  // rm -rf <目标>：任一操作数命中即可，目标前后的旗标与其它操作数不能规避
  if (
    head === "rm" &&
    normArgv[1] === "-rf" &&
    patternWords.length === 3 &&
    patternWords[1] === "-rf" &&
    !patternWords[2].includes("*")
  ) {
    const target = patternWords[2];
    return normArgv
      .slice(2)
      .some(
        (o) =>
          o === target ||
          (o.startsWith(target) && /^[*?[\]]*$/.test(o.slice(target.length))),
      );
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

/** 交互式选取、编辑与预览不会整体写入暂存区 */
function isGitAddPreviewFlag(arg: string): boolean {
  if (arg.startsWith("--")) {
    return (
      arg === "--patch" ||
      arg === "--interactive" ||
      arg === "--edit" ||
      arg === "--dry-run"
    );
  }
  return /^-[a-zA-Z]*[pine]/.test(arg);
}

/** 解析 pathspec 前缀 magic；短形式 :! 与 :^ 等价 exclude，":" 与 ":/" 指向全树 */
function gitPathspecMagic(p: string): {
  exclude: boolean;
  literal: boolean;
  rest: string;
} {
  if (!p.startsWith(":")) return { exclude: false, literal: false, rest: p };
  if (p[1] === "!" || p[1] === "^") {
    return { exclude: true, literal: false, rest: p.slice(2) };
  }
  if (p[1] === "/") {
    return { exclude: false, literal: false, rest: p.slice(2) };
  }
  if (p[1] === "(") {
    const close = p.indexOf(")", 2);
    if (close !== -1) {
      const magics = p.slice(2, close).split(",");
      return {
        exclude: magics.includes("exclude"),
        literal: magics.includes("literal"),
        rest: p.slice(close + 1),
      };
    }
  }
  return { exclude: false, literal: false, rest: p.slice(1) };
}

/** pathspec 解析后是否覆盖整个工作目录（含其上级目录） */
function pathspecCoversCwd(rest: string, cwd: string): boolean {
  const rel = path.relative(path.resolve(cwd, rest), cwd);
  return (
    rel === "" ||
    (rel !== ".." && !rel.startsWith(".." + path.sep) && !path.isAbsolute(rel))
  );
}

/** git add 是否属于「没有明确文件范围」的暂存；排除项不算正向选择 */
function gitAddIsFullScope(words: ShellWord[], cwd?: string): boolean {
  const stripped = operandWords(words);
  if (stripped.length < 2 || basenames(stripped[0].value) !== "git") {
    return false;
  }
  let i = 1;
  while (i < stripped.length && stripped[i].value.startsWith("-")) {
    i += GIT_GLOBAL_VALUE_OPTIONS[stripped[i].value] === true ? 2 : 1;
  }
  if (stripped[i]?.value !== "add") return false;

  const pathspecs: ShellWord[] = [];
  let afterSeparator = false;
  let preview = false;
  let indirect = false;
  for (let j = i + 1; j < stripped.length; j++) {
    const w = stripped[j];
    // 重定向目标不是 pathspec，`git add -A >/tmp/x` 不能冒充明确范围
    if (w.target !== null) continue;
    const arg = w.value;
    if (afterSeparator) {
      pathspecs.push(w);
      continue;
    }
    if (arg === "--") {
      afterSeparator = true;
      continue;
    }
    if (arg.startsWith("-")) {
      if (
        arg === "--pathspec-from-file" ||
        arg.startsWith("--pathspec-from-file=")
      ) {
        // 间接 pathspec 收集完 preview 再判定，两种参数先后都要生效
        indirect = true;
        continue;
      }
      if (isGitAddPreviewFlag(arg)) preview = true;
      continue;
    }
    pathspecs.push(w);
  }
  // 交互选取与预览不会整体写入暂存区，且优先于 indirect 判定
  if (preview) return false;
  if (indirect) return true;

  let hasPositive = false;
  for (const w of pathspecs) {
    const { exclude, literal, rest } = gitPathspecMagic(w.value);
    if (exclude) continue;
    hasPositive = true;
    // 动态取值无法静态确认范围
    if (w.dynamic || w.glob) return true;
    if (
      rest === "" ||
      rest === "." ||
      rest === ".." ||
      rest === "./" ||
      rest === "../" ||
      (cwd !== undefined && pathspecCoversCwd(rest, cwd))
    ) {
      return true;
    }
    // literal magic 中的通配符是文件名的字面部分，仍算确切文件
    if (!literal && /[*?[\]]/.test(rest)) return true;
  }
  return !hasPositive;
}

const DOWNLOADERS: Record<string, true> = { curl: true, wget: true };

const STDIN_SHELLS: Record<string, true> = {
  sh: true,
  bash: true,
  zsh: true,
  dash: true,
  ash: true,
  ksh: true,
  fish: true,
  csh: true,
  tcsh: true,
  source: true,
  ".": true,
};

const STDIN_SCRIPTS: Record<string, true> = {
  node: true,
  bun: true,
  deno: true,
  tsx: true,
  "ts-node": true,
  perl: true,
  ruby: true,
  php: true,
  lua: true,
  luajit: true,
  osascript: true,
  rscript: true,
};

const PY_STR = String.raw`(?:"(?:[^"\\\r\n]|\\[^\r\n])*"|'(?:[^'\\\r\n]|\\[^\r\n])*')`;

/** Python 字段访问只支持下标与 .get("字面量") */
const PY_FIELD = String.raw`(?:\s*\[\s*(?:${PY_STR}|-?\d+)\s*\]|\s*\.\s*get\s*\(\s*${PY_STR}\s*\))*`;

/** 仅放行固定的「读取 stdin JSON 并打印字段」脚本，其余 python -c 一律保守拦截 */
const SAFE_JSON_SCRIPT = new RegExp(
  String.raw`^\s*import\s+(?:json\s*,\s*sys|sys\s*,\s*json)\s*;\s*print\s*\(\s*json\s*\.\s*(?:load\s*\(\s*sys\s*\.\s*stdin\s*\)|loads\s*\(\s*sys\s*\.\s*stdin\s*\.\s*read\s*\(\s*\)\s*\))${PY_FIELD}\s*\)\s*;?\s*$`,
);

/** 显式 stdin 路径操作数：与管道下载组合时等于把下载体当程序 */
const STDIN_PATHS: Record<string, true> = {
  "/dev/stdin": true,
  "/dev/fd/0": true,
  "/proc/self/fd/0": true,
};

type InterpreterKind = "python" | "shell" | "script";

function interpreterKind(head: string): InterpreterKind | null {
  if (/^python(?:\d+(?:\.\d+)*)?$/.test(head)) return "python";
  if (STDIN_SHELLS[head] === true) return "shell";
  if (STDIN_SCRIPTS[head] === true) return "script";
  return null;
}

/** 带独立取值的解释器旗标：其取值不是脚本操作数 */
const VALUE_FLAGS: Record<string, true> = {
  "-W": true,
  "-X": true,
  "-o": true,
  "+o": true,
  "-O": true,
  "+O": true,
  "--rcfile": true,
  "--init-file": true,
};

/** 切出脚本操作数；dash 表示首个操作数之前出现了独立的 `-`（脚本取自 stdin） */
function scanOperands(rest: string[]): { operands: string[]; dash: boolean } {
  const operands: string[] = [];
  let dash = false;
  for (let k = 0; k < rest.length; k++) {
    const a = rest[k];
    if (VALUE_FLAGS[a] === true) k++;
    else if (a === "-") dash = dash || operands.length === 0;
    else if (!a.startsWith("-")) operands.push(a);
  }
  return { operands, dash };
}

function interpreterExecutesStdin(words: ShellWord[]): boolean {
  const args = operandWords(words);
  const argv = args.map((w) => w.value);
  if (argv.length === 0) return false;
  const head = basenames(argv[0]).toLowerCase();
  const kind = interpreterKind(head);
  if (kind === null) return false;
  const python = kind === "python";
  const shell = kind === "shell";
  const script = kind === "script";
  // 动态参数可能改变代码或 stdin 操作数，不能按字面量放行
  if (args.some((w) => w.dynamic)) return true;
  const rest = argv.slice(1);
  const { operands, dash } = scanOperands(rest);
  if (dash || operands.some((a) => STDIN_PATHS[a] === true)) return true;
  if (python) {
    const codeIdx = rest.findIndex(
      (a) => a === "-c" || /^-[a-zA-Z]*c[a-zA-Z]*$/.test(a),
    );
    if (codeIdx !== -1) {
      return (
        codeIdx + 1 >= rest.length || !SAFE_JSON_SCRIPT.test(rest[codeIdx + 1])
      );
    }
    return operands.length === 0;
  }
  if (shell) {
    // -c 的代码能读取管道体，不能把它当作脚本文件名
    return (
      rest.some((a) => /^-[a-zA-Z]*[sc][a-zA-Z]*$/.test(a)) ||
      operands.length === 0
    );
  }
  if (script) {
    // perl/ruby/php 的 -e/-r 内联代码可以读取管道体
    return (
      operands.length === 0 ||
      rest.some((a) => /^-[a-zA-Z]*[er][a-zA-Z]*$/.test(a))
    );
  }
  return false;
}

/** 脚本正文里是否有下载器调用 */
function fetchesRemote(script: string): boolean {
  return commandNodes(tokenizeShell(script)).some((node) => {
    const argv = operandWords(node.words);
    return (
      argv.length > 0 &&
      DOWNLOADERS[basenames(argv[0].value).toLowerCase()] === true
    );
  });
}

/** 下载结果经 $()、<()、<<<、< <() 等非管道通道成为被执行的代码 */
function remoteCodeExecuted(words: ShellWord[]): boolean {
  const args = operandWords(words);
  if (args.length === 0) return false;
  const head = basenames(args[0].value).toLowerCase();
  const evaluator = head === "eval" || head === "source" || head === ".";
  if (!evaluator && interpreterKind(head) === null) return false;
  const remote = (w: ShellWord) => w.subs.some(fetchesRemote);
  // 重定向到 stdin 的下载结果等同于管道
  if (words.some((w) => w.target === "in" && remote(w))) return true;
  const code = evaluator
    ? args.slice(1)
    : args.slice(1).filter((w) => !w.value.startsWith("-")).slice(0, 1);
  return code.some(remote);
}

function downloadPipeExecutes(nodes: ShellCmd[]): boolean {
  let downloader = false;
  let piped = false;
  for (const node of nodes) {
    if (!piped) downloader = false;
    const argv = operandWords(node.words).map((w) => w.value);
    if (argv.length > 0) {
      if (!downloader) {
        downloader = DOWNLOADERS[basenames(argv[0]).toLowerCase()] === true;
      } else if (interpreterExecutesStdin(node.words)) {
        return true;
      }
    }
    piped = node.pipeNext;
  }
  return false;
}

function isDownloadRulePattern(pattern: string): boolean {
  return (
    (pattern.startsWith("curl ") || pattern.startsWith("wget ")) &&
    BUILTIN_COMMANDS.some((rule) => rule.value === pattern)
  );
}

function matchCommandNodes(
  nodes: ShellCmd[],
  tokens: ShellToken[],
  pattern: string,
  cwd?: string,
): boolean {
  if (isDownloadRulePattern(pattern)) {
    return (
      downloadPipeExecutes(nodes) ||
      nodes.some((c) => remoteCodeExecuted(c.words))
    );
  }
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
  if (
    patternWords.length === 3 &&
    patternWords[0] === "git" &&
    patternWords[1] === "add" &&
    (patternWords[2] === "-A" || patternWords[2] === ".")
  ) {
    return nodes.some((c) => gitAddIsFullScope(c.words, cwd));
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
  const shells = new Set(["sh", "bash", "dash", "zsh", "ash", "ksh", "fish"]);
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
  const caseInsensitive = process.platform === "darwin";
  const re = R.includes("*")
    ? new RegExp(`^${globToRegExpSource(R)}$`, caseInsensitive ? "i" : undefined)
    : undefined;
  const samePath = (a: string, b: string) =>
    re ? re.test(a) : a === b || (caseInsensitive && a.toLowerCase() === b.toLowerCase());
  if (samePath(C, R)) return true;
  const realC = resolveReal(C);
  if (realC !== C && samePath(realC, R)) return true;
  if (re) {
    // 通配部分不能 realpath，先解析固定目录前缀
    const prefix = path.dirname(R.slice(0, R.indexOf("*")));
    const realPrefix = resolveReal(prefix);
    if (realPrefix !== prefix) {
      const realRe = new RegExp(
        `^${globToRegExpSource(realPrefix + R.slice(prefix.length))}$`,
        caseInsensitive ? "i" : undefined,
      );
      if (realRe.test(C) || realRe.test(realC)) return true;
    }
  } else {
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

function isMissingPathError(error: unknown): boolean {
  return (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    error.code === "ENOENT"
  );
}

function protectedLinkTarget(
  candidate: string,
  policy: Policy,
  cwd: string,
  home: string,
): boolean {
  const hits = (p: string, origin: string) =>
    policy.paths.some((rule) => {
      const R = absoluteForm(rule.value, cwd, home);
      // 共享目录链接只改变路径写法，不扩大原有的确切授权
      if (R === origin || R.startsWith(origin + path.sep)) return false;
      return pathRuleMatchesFull(p, rule.value, cwd, home);
    });
  const seen = new Set<string>();
  const original = path.resolve(candidate);
  const parts = original.split(path.sep);
  let resolved = "";
  let prefixEnd = 0;
  let linkOrigin = "";
  for (let i = 1; i < parts.length; i++) {
    prefixEnd += parts[i].length + path.sep.length;
    let cur =
      resolved === "" ? path.sep + parts[i] : resolved + path.sep + parts[i];
    for (;;) {
      // link 环无法确认最终落点，保守按受保护处理
      if (seen.has(cur)) return true;
      let target: string | undefined;
      try {
        if (lstatSync(cur).isSymbolicLink()) {
          target = path.resolve(path.dirname(cur), readlinkSync(cur));
        }
      } catch (error) {
        // 路径到此不存在，更深的组件也无法构成链接
        if (isMissingPathError(error)) break;
        return true;
      }
      if (target === undefined) break;
      seen.add(cur);
      linkOrigin = original.slice(0, prefixEnd);
      if (hits(target, linkOrigin)) return true;
      cur = target;
    }
    resolved = cur;
    if (linkOrigin && hits(resolved, linkOrigin)) return true;
  }
  return false;
}

/** 确切路径只读授权：只认精确路径；链接展开后落到被禁目标的条目按受禁处理 */
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
          // macOS 默认大小写不敏感，.ENV 与 .env 是同一个文件
          /^\.env(?:\..*)?$/i.test(token)
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

/** 嵌套脚本（$()、sh -c、heredoc 正文）的最大解析层数，超出按拦截处理 */
const MAX_NEST_DEPTH = 24;

export function evaluateGuard(
  input: GuardInput,
  policy: Policy,
  allowReadExempt = true,
  depth = 0,
): GuardResult {
  if (input.tool === "bash") {
    if (depth > MAX_NEST_DEPTH) {
      return {
        block: true,
        reason: "! FORBIDDEN COMMAND\nreason: 命令嵌套层级过深，无法安全审计",
      };
    }
    const command = expandHomeInText(input.command, input.home);
    const tokens = tokenizeShell(command);
    const nodes = commandNodes(tokens);
    const argvs = nodes.map((c) => c.words.map((w) => w.value));

    for (const rule of policy.commands) {
      if (matchCommandNodes(nodes, tokens, rule.value, input.cwd)) {
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
        depth + 1,
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
          owner !== undefined && interpreterExecutesStdin(owner.words);
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

  const layers: Array<{
    name: string;
    source: string | null | undefined;
    project: boolean;
  }> = [
    { name: "全局配置", source: input.globalSource, project: false },
    { name: "项目配置", source: input.projectSource, project: true },
  ];

  for (const { name, source, project } of layers) {
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
    // 项目配置来自被审查的仓库，只能授权项目目录内的文件，不能放行家目录凭据
    const allowReadOps = project
      ? parsed.layer.allowReadOps.filter((op) => {
          if (op.type === "remove") return true;
          const rel = path.relative(
            ctx.cwd,
            absoluteForm(op.value, ctx.cwd, ctx.home),
          );
          if (
            rel !== "" &&
            rel !== ".." &&
            !rel.startsWith(".." + path.sep) &&
            !path.isAbsolute(rel)
          ) {
            return true;
          }
          errors.push(
            `${name}: allow_read_paths 仅允许项目目录内的路径: ${op.value}`,
          );
          return false;
        })
      : parsed.layer.allowReadOps;
    allowReadPaths = applyOps(allowReadPaths, allowReadOps, "path", ctx);
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
