/**
 * guard 的 shell 词法层：把一行命令拆成独立命令与词，并对 argv 做前缀匹配。
 *
 * 词上保留四处信息：引用剥掉后的字面值、通配是否生效、取值是否可静态确定、是否为重定向目标。
 * 判定层据此区分 `rm -rf "$d"`（已知字符串）与 `rm -rf $d/*`（变量可能展开为空）、
 * `ls .env`（元数据）与 `cat < .env`（读取）。
 */

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

type ShellToken =
  | { kind: "word"; value: string; activeGlob: boolean; dynamic: boolean }
  | { kind: "op"; value: string }
  /** 活跃命令替换（$() 或反引号）捕获到的内嵌脚本 */
  | { kind: "sub"; value: string }
  /** heredoc 正文；quoted 仅表示不做替换展开，正文仍可能被解释器当作程序；owner 是所属命令首 token 下标 */
  | { kind: "heredoc"; value: string; quoted: boolean; owner: number };

/** 查表用无原型对象：命令名可能撞上 `constructor`、`toString` 这类继承属性 */
export function lookup<T>(entries: Record<string, T>): Record<string, T> {
  return Object.assign(Object.create(null), entries);
}

const CONTROL_OPS: Record<string, true> = lookup<true>({
  "|": true,
  "||": true,
  "&&": true,
  ";": true,
  "&": true,
  "\n": true,
  "(": true,
  ")": true,
});

/** 扫描 $() 的平衡括号正文（感知引号与转义） */
function scanCommandSub(input: string, openParen: number): { body: string; end: number } {
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

function scanBacktick(input: string, start: number): { body: string; end: number } {
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
function heredocDelimiter(input: string, start: number): { delim: string; quoted: boolean; end: number } {
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
function heredocBody(input: string, start: number, delim: string, dash: boolean): { body: string; end: number } {
  let i = start;
  const lines: string[] = [];
  for (;;) {
    const nl = input.indexOf("\n", i);
    const stop = nl === -1 ? input.length : nl;
    const line = input.slice(i, stop);
    if ((dash ? line.replace(/^\t+/, "") : line) === delim) {
      return { body: lines.join("\n"), end: nl === -1 ? input.length : nl + 1 };
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
  let pending: Array<{ delim: string; quoted: boolean; dash: boolean; owner: number }> = [];

  // heredoc 正文在行尾换行之后才出现，必须在此处消费，避免被当成命令或路径
  const flushHeredocs = () => {
    for (const h of pending) {
      const consumed = heredocBody(input, i, h.delim, h.dash);
      tokens.push({ kind: "heredoc", value: consumed.body, quoted: h.quoted, owner: h.owner });
      i = consumed.end;
    }
    pending = [];
  };

  // 命令替换在单引号之外始终会执行（包括双引号内）：正文交给递归判定，词标记为动态取值
  const readSub = (open: number): number => {
    const sub = input[open] === "`" ? scanBacktick(input, open) : scanCommandSub(input, open);
    if (sub.body.trim() !== "") tokens.push({ kind: "sub", value: sub.body });
    return sub.end + 1;
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
        pending.push({ delim: delim.delim, quoted: delim.quoted, dash: heredocOp[2] === "<<-", owner: cmdStart });
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
    // 反斜杠换行是续行符：两个字符都不存在，前后两段拼成同一个词
    if (ch === "\\" && input[i + 1] === "\n") {
      i += 2;
      continue;
    }

    let word = "";
    let activeGlob = false;
    let dynamic = false;
    while (i < input.length) {
      const c = input[i];
      if (" \t\r\n|;&()<>".includes(c)) break;
      if (input.startsWith("||", i) || input.startsWith("&&", i)) break;

      // 命令替换在单引号之外始终会执行，包括双引号内
      if (c === "$" && input[i + 1] === "(") {
        dynamic = true;
        i = readSub(i + 1);
        continue;
      }
      if (c === "`") {
        dynamic = true;
        i = readSub(i);
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
            dynamic = true;
            i = readSub(i + 1);
            continue;
          }
          if (d === "`") {
            dynamic = true;
            i = readSub(i);
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
        if (input[i + 1] !== "\n") word += input[i + 1];
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
 * 重定向操作符（<, >, >>）后的文件名保留在当前 argv 中，路径判定才能捕获 `cat < .env`；
 * startToken 指向命令段首个 token（含前置重定向），与 heredoc token 的 owner 对齐，
 * 否则 `2>/tmp/err bash <<EOF` 的正文会因找不到所属命令被当成无害数据。
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
      if (words.length === 0) startToken = pendingStart ?? idx;
      words.push({ value: t.value, glob: t.activeGlob, dynamic: t.dynamic, target: pendingTarget });
      pendingTarget = null;
      continue;
    }
    if (t.kind !== "op") {
      // 命令替换 sub token 属于当前命令段的 token 范围，同样计入起点
      if (t.kind === "sub" && words.length === 0 && pendingStart === null) pendingStart = idx;
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
    if (t.value === "<<" || t.value === "<<-" || /^\d*>&/.test(t.value)) continue;
    pendingTarget = t.value.includes(">") ? "out" : "in";
  }
  flush(false);
  return out;
}

export function basenames(word: string): string {
  if (word === "/" || word === "." || word === "..") return word;
  const slash = word.lastIndexOf("/");
  return slash === -1 ? word : word.slice(slash + 1);
}

function stripLeadingAssignments(words: string[]): string[] {
  let i = 0;
  while (i < words.length && /^[A-Za-z_][A-Za-z0-9_]*=/.test(words[i])) i++;
  return words.slice(i);
}

/**
 * 包装器命令：值为带独立取值的选项（要连后一个词一起跳过）。
 * 不在表里的命令本身就是被检查的目标。
 */
const WRAPPER_VALUE_FLAGS: Record<string, string[]> = lookup<string[]>({
  env: ["-u", "--unset", "-C", "--chdir", "-S", "--split-string"],
  sudo: ["-u", "-g", "-p", "--user", "--group", "--prompt"],
  doas: ["-u", "-g"],
  timeout: ["-k", "--kill-after", "-s", "--signal"],
  nice: ["-n", "--adjustment"],
  nohup: [],
  command: [],
  builtin: [],
  exec: [],
  setsid: [],
  stdbuf: [],
  ionice: [],
  watch: [],
  xargs: [],
  time: [],
});

/** 剥离包装器命令（如 sudo, env, nohup, timeout 等）与前置变量赋值 */
export function stripWrappers(words: string[]): string[] {
  let w = stripLeadingAssignments(words);
  for (;;) {
    const head = w.length > 0 ? basenames(w[0]) : "";
    const valueFlags = WRAPPER_VALUE_FLAGS[head];
    if (valueFlags === undefined) return w;
    let j = 1;
    while (j < w.length && w[j].startsWith("-")) {
      if (w[j] === "--") {
        j++;
        break;
      }
      j += valueFlags.includes(w[j]) ? 2 : 1;
    }
    // timeout 的时长、env/sudo 后的变量赋值都不是被包装的命令
    if (head === "timeout" && j < w.length) j++;
    while (j < w.length && /^[A-Za-z_][A-Za-z0-9_]*=/.test(w[j])) j++;
    // 裸 `env -0` 之类没有后续命令，保留原样交给内置规则判定
    if (j >= w.length) return w;
    w = stripLeadingAssignments(w.slice(j));
  }
}

/** 剥离包装器后的词表；长度不变说明没有包装器 */
export function stripWrapperWords(words: ShellWord[]): ShellWord[] {
  const kept = stripWrappers(words.map((w) => w.value)).length;
  return kept === words.length ? words : words.slice(words.length - kept);
}

/** 重定向目标不是命令操作数；剥离包装器前缀后返回剩余词 */
export function operandWords(words: ShellWord[]): ShellWord[] {
  return stripWrapperWords(words.filter((w) => w.target === null));
}

/** 剥离包装器与重定向目标后的 argv */
export function argvOf(cmd: ShellCmd): string[] {
  return operandWords(cmd.words).map((w) => w.value);
}

/** 折叠连续通配符防止正则回溯；正则元字符转义，`*` 匹配任意长度（含 /） */
export function globToRegExpSource(pattern: string): string {
  let out = "";
  for (const ch of pattern.replace(/\*{2,}/g, "*")) {
    if (ch === "*") out += ".*";
    else if (/[\\^$+?.()|[\]{}]/.test(ch)) out += `\\${ch}`;
    else out += ch;
  }
  return out;
}

/** 规则文本拆成词；含控制符的规则不是简单命令，返回 null */
export function patternWords(pattern: string): string[] | null {
  const tokens = tokenizeShell(pattern);
  if (tokens.some((t) => t.kind === "op" && CONTROL_OPS[t.value])) return null;
  const cmd = commandNodes(tokens)[0];
  const words = cmd ? cmd.words.map((w) => w.value) : [];
  return words.length > 0 ? words : null;
}

/**
 * argv 前缀匹配：首词按 basename 比对，其余按词相等，末词允许跟上通配续写
 * （`find ~` 因此只命中家目录本身，`find ~/Code` 不受影响）。
 */
export function argvMatches(args: string[], patternWords: string[]): boolean {
  if (args.length < patternWords.length) return false;
  for (let i = 0; i < patternWords.length; i++) {
    const a = args[i];
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
    if (a.startsWith(p) && /^[*?[\]]*$/.test(a.slice(p.length))) continue;
    return false;
  }
  return true;
}

const DOWNLOADERS: Record<string, true> = lookup<true>({ curl: true, wget: true });

const SHELLS: Record<string, true> = lookup<true>({
  sh: true,
  bash: true,
  zsh: true,
  dash: true,
  ash: true,
  ksh: true,
});

const SCRIPT_RUNNERS: Record<string, true> = lookup<true>({
  node: true,
  bun: true,
  deno: true,
  perl: true,
  ruby: true,
  php: true,
  lua: true,
  luajit: true,
});

/** 显式 stdin 操作数：出现即等于把管道体或 heredoc 当程序 */
const STDIN_PATHS: Record<string, true> = lookup<true>({
  "/dev/stdin": true,
  "/dev/fd/0": true,
  "/proc/self/fd/0": true,
});

/**
 * 内联程序标志按解释器区分：shell 只有 -c 给程序（-e/-x/-u 仍是选项，脚本仍来自 stdin），
 * node/bun/deno 另有 -e/--eval/-p/--print，perl/ruby/lua 用 -e，php 用 -r，python 用 -c/-m。
 */
function hasInlineProgram(head: string, flags: string[]): boolean {
  if (SHELLS[head] === true) return flags.some((f) => /^-[a-zA-Z]*c/.test(f));
  if (head === "php") return flags.some((f) => /^-[a-zA-Z]*r/.test(f));
  if (head.startsWith("python")) return flags.some((f) => /^-[a-zA-Z]*[cm]/.test(f));
  if (head === "perl" || head === "ruby" || head === "lua" || head === "luajit") {
    return flags.some((f) => /^-[a-zA-Z]*e/.test(f) || f === "--eval");
  }
  return flags.some((f) => /^-[a-zA-Z]*[ep]/.test(f) || f === "--eval" || f === "--print");
}

/**
 * 该命令是否从 stdin 读取要执行的程序。
 * shellsOnly 为真时只认 shell：heredoc 正文只按 shell 脚本递归，python 之类的
 * 正文是另一种语言，按 shell 解释只会误报。
 */
export function executesStdinProgram(words: ShellWord[], shellsOnly = false): boolean {
  const args = operandWords(words);
  if (args.length === 0) return false;
  const head = basenames(args[0].value).toLowerCase();
  const shell = SHELLS[head] === true;
  const runner =
    !shellsOnly && (SCRIPT_RUNNERS[head] === true || /^python(?:\d+(?:\.\d+)*)?$/.test(head));
  if (!shell && !runner) return false;
  const rest = args.slice(1).map((w) => w.value);
  const flags = rest.filter((a) => a.startsWith("-"));
  const operands = rest.filter((a) => !a.startsWith("-"));
  // 内联程序优先于 `-` 与 /dev/stdin 操作数
  if (hasInlineProgram(head, flags)) return false;
  // 显式 stdin 操作数（或 `-`）都是把输入当程序
  if (rest.some((a) => STDIN_PATHS[a] === true || a === "-")) return true;
  // shell 的 -s 表示从 stdin 读程序，其后即使跟位置参数也仍然是 stdin 程序；
  // -o 每个都要取值（`sh -o pipefail`），这些词不是脚本文件名
  if (shell) {
    const options = flags.filter((f) => /^-[a-zA-Z]*o/.test(f)).length;
    return flags.some((f) => /^-[a-zA-Z]*s/.test(f)) || operands.length <= options;
  }
  return operands.length === 0;
}

/** 同一管道里下载器下游有命令从 stdin 读程序时的两端命令名 */
export function downloadPipeExecutes(
  nodes: ShellCmd[],
): { downloader: string; interpreter: string } | null {
  let downloader: string | undefined;
  for (const node of nodes) {
    const args = operandWords(node.words);
    const head = args.length === 0 ? "" : basenames(args[0].value).toLowerCase();
    if (downloader === undefined) {
      if (head !== "" && DOWNLOADERS[head] === true) downloader = head;
    } else if (head !== "" && executesStdinProgram(node.words)) {
      return { downloader, interpreter: head };
    }
    if (!node.pipeNext) downloader = undefined;
  }
  return null;
}

/** 提取嵌套在 shell wrapper（如 sh -c, bash -lc, eval）中的内嵌脚本；命令替换由词法层产出 sub token */
export function embeddedScripts(argvs: string[][]): string[] {
  const scripts: string[] = [];
  for (const argv of argvs) {
    const stripped = stripWrappers(argv);
    if (stripped.length === 0) continue;
    const head = basenames(stripped[0]);
    if (SHELLS[head] === true) {
      const cIdx = stripped.findIndex((arg, idx) => idx > 0 && /^-[a-zA-Z]*c[a-zA-Z]*$/.test(arg));
      if (cIdx !== -1 && cIdx + 1 < stripped.length) scripts.push(stripped[cIdx + 1]);
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

/** 扫描自由文本中的命令替换；无引用 heredoc 正文在展开阶段会执行其中的替换 */
export function scanSubsInText(text: string): string[] {
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
