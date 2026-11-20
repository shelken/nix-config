/**
 * guard 的权限策略层：内置路径规则 + 全局权限文件 + 项目权限文件依次叠加，
 * 路径规则在加载时编译成绝对 glob 正则，判定时只做匹配与软链接解析。
 */

import { existsSync, readFileSync, realpathSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";
import { globToRegExpSource } from "./shell.ts";

export type RuleSource = "builtin" | "user";

/** 命令规则：match 是展开 `~`/`$HOME` 后用于匹配的文本，value 是展示用原文 */
export type CommandRule = {
  value: string;
  match: string;
  reason?: string;
  source: RuleSource;
  config: string;
};

/** 路径规则：value 在加载时编译成绝对 glob 正则；except 是内置例外（按 basename 匹配） */
export type PathRule = {
  value: string;
  reason?: string;
  source: RuleSource;
  config: string;
  regexp: RegExp;
  /** 相对规则（如 `.env.*`）额外编译「任意深度」形态，软链接目标在 cwd 之外时也按规则匹配 */
  anyDepth?: RegExp;
  except: RegExp[];
};

export type Policy = {
  default_reason?: string;
  /** 内置命令规则由 guard.ts 的检查函数承担，这里只放用户规则 */
  commands: CommandRule[];
  paths: PathRule[];
};

type AddOp = { type: "add"; value: string; reason?: string };
type GlobalOp = AddOp | { type: "remove"; value: string };

type ParsedLayer = {
  default_reason?: string;
  commandOps: GlobalOp[];
  pathOps: GlobalOp[];
  errors: string[];
};

type ParseLayerResult =
  | { ok: true; layer: ParsedLayer }
  | { ok: false; error: string };

/** layer：整层配置没能加载；item：只有其中一项被忽略，其余规则照常生效 */
export type BuildError = { message: string; scope: "layer" | "item" };
export type BuildPolicyResult = { policy: Policy; errors: BuildError[] };
/** YAML 解析由宿主提供：guard 自己不带 YAML 库 */
export type YamlParser = (source: string) => unknown;
export type PermissionPaths = { globalPath: string; projectPath: string };
export type LoadFailure = { path: string; message: string; scope: BuildError["scope"] };
export type LoadPolicyResult = { policy: Policy; failures: LoadFailure[] };
type ReadConfigResult =
  | { status: "missing" }
  | { status: "ok"; text: string }
  | { status: "error"; message: string };

export const BUILTIN_COMMAND_CONFIG = "guard#BUILTIN_COMMANDS";
const BUILTIN_PATH_CONFIG = "guard#BUILTIN_PATHS";

export function expandHomeInText(text: string, home: string): string {
  if (!home) return text;
  let s = text.replaceAll("${HOME}", home);
  s = s.replace(/\$HOME\b/g, home);
  s = s.replace(/(^|[^A-Za-z0-9_])~(?=\/|$|[^A-Za-z0-9_/])/g, (_m, pre: string) => pre + home);
  return s;
}

/**
 * 剥离 OMP 工具行锚定与格式选择器（如 :50-200, :raw, :conflicts, :10:raw 等）。
 * 针对首个选择器冒号截断，并兼容 Windows 盘符（如 C:\）。
 */
export function stripOmpSelector(p: string): string {
  const startIdx = process.platform === "win32" && /^[a-zA-Z]:/.test(p) ? 2 : 0;
  const colonIdx = p.indexOf(":", startIdx);
  return colonIdx > 0 ? p.slice(0, colonIdx) : p;
}

export function normPath(p: string, cwd: string, home: string): string {
  return path.normalize(path.resolve(cwd, expandHomeInText(p.trim(), home)));
}

/**
 * 路径规则是否命中：候选路径按原样与软链接解析后的真实路径各试一次，例外按同一形态判定。
 * 相对规则对解析后的形态再试一次「任意深度」形态，`.env.tpl` 链接到 `.env` 时因此仍被拦。
 */
export function pathRuleMatches(rule: PathRule, candidate: string): boolean {
  const forms = [candidate];
  try {
    const real = realpathSync(candidate);
    if (real !== candidate) forms.push(real);
  } catch {
    // 路径不存在（新建、删除目标）时只按原样匹配
  }
  return forms.some(
    (form) =>
      (rule.regexp.test(form) || rule.anyDepth?.test(form) === true) &&
      !rule.except.some((e) => e.test(path.basename(form))),
  );
}

type BuiltinPath = { value: string; reason: string; except?: string[] };

const ENV_EXCEPT = ["*.tpl", "*.example", "*.sample", "*.template"];

function dirRules(dir: string, reason: string): BuiltinPath[] {
  return [
    { value: dir, reason },
    { value: `${dir}/*`, reason },
  ];
}

function valueRules(values: string[], reason: string): BuiltinPath[] {
  return values.map((value) => ({ value, reason }));
}

const BUILTIN_PATHS: BuiltinPath[] = [
  { value: "~/.ssh", reason: "SSH 配置与密钥目录" },
  { value: "~/.ssh/*", reason: "SSH 私钥与主机密钥", except: ["config", "known_hosts*", "*.pub"] },
  ...dirRules("~/.aws", "云厂商凭据"),
  ...dirRules("~/.azure", "云厂商凭据"),
  ...dirRules("~/.gcp", "云厂商凭据"),
  ...dirRules("~/.gnupg", "GnuPG 钥匙环"),
  ...dirRules("~/.config/sops/age", "SOPS age 私钥"),
  ...valueRules(
    ["~/.netrc", "~/.pypirc", "~/.git-credentials", "~/.config/gh/hosts.yml", "~/.kube/config", "~/.docker/config.json"],
    "认证与令牌配置",
  ),
  ...valueRules(
    ["~/.bash_history", "~/.zsh_history", "~/.zhistory", "~/.node_repl_history", "~/.python_history"],
    "终端历史",
  ),
  { value: ".env", reason: "环境变量文件" },
  { value: ".env.*", reason: "环境变量文件", except: ENV_EXCEPT },
];

type ExpandCtx = { home: string; cwd: string };

function compilePathRule(
  value: string,
  reason: string | undefined,
  except: string[],
  source: RuleSource,
  config: string,
  ctx: ExpandCtx,
): PathRule {
  const absolute = normPath(value, ctx.cwd, ctx.home);
  const relative = expandHomeInText(value, ctx.home);
  // 任意深度只给内置环境文件规则：用户相对规则保持 cwd 锚定语义
  const anyDepth =
    source === "builtin" && !relative.startsWith("/")
      ? new RegExp(`(^|/)${globToRegExpSource(relative)}$`)
      : undefined;
  return {
    value,
    reason,
    source,
    config,
    regexp: new RegExp(`^${globToRegExpSource(absolute)}$`),
    anyDepth,
    except: except.map((e) => new RegExp(`^${globToRegExpSource(e)}$`)),
  };
}

function isNonEmptyString(v: unknown): v is string {
  return typeof v === "string" && v.trim() !== "";
}

/** `-值` 删除同名规则；`--` 开头的值不是删除语法 */
function removalValue(raw: string): string | null {
  const t = raw.trim();
  return t.startsWith("-") && !t.startsWith("--") && t.length > 1 ? t.slice(1) : null;
}

function parseListOps(
  list: unknown,
  valueKey: "pattern" | "path",
): { ops: GlobalOp[]; errors: string[] } {
  if (list == null) return { ops: [], errors: [] };
  if (!Array.isArray(list)) return { ops: [], errors: ["配置项必须为列表数组"] };

  const ops: GlobalOp[] = [];
  const errors: string[] = [];
  for (let idx = 0; idx < list.length; idx++) {
    const item = list[idx];
    if (isNonEmptyString(item)) {
      const remove = removalValue(item);
      ops.push(remove !== null ? { type: "remove", value: remove } : { type: "add", value: item.trim() });
      continue;
    }
    if (item && !Array.isArray(item) && typeof item === "object") {
      const obj = item as Record<string, unknown>;
      if (!isNonEmptyString(obj[valueKey])) {
        errors.push(`第 ${idx + 1} 项缺少必要的 '${valueKey}' 属性`);
        continue;
      }
      ops.push({ type: "add", value: obj[valueKey].trim(), reason: isNonEmptyString(obj.reason) ? obj.reason : undefined });
      continue;
    }
    errors.push(`第 ${idx + 1} 项格式无效`);
  }
  return { ops, errors };
}

function parseLayerYaml(source: string, parseYaml: YamlParser): ParseLayerResult {
  let doc: unknown;
  try {
    doc = parseYaml(source);
  } catch (e) {
    return { ok: false, error: e instanceof Error ? e.message : String(e) };
  }
  if (doc == null) return { ok: true, layer: { commandOps: [], pathOps: [], errors: [] } };
  if (typeof doc !== "object" || Array.isArray(doc)) {
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
  if (isNonEmptyString(root.default_reason)) layer.default_reason = root.default_reason;
  return { ok: true, layer };
}

/** 全局层：`-值` 按规则原文删除同名规则，相同原文的新规则就地覆盖；路径规则与内置规则同路，`-值` 可撤掉内置规则。 */
function applyGlobalOps<T extends { value: string }>(
  rules: T[],
  ops: GlobalOp[],
  make: (op: AddOp) => T,
): T[] {
  let out = rules.slice();
  for (const op of ops) {
    if (op.type === "remove") {
      out = out.filter((r) => r.value !== op.value);
      continue;
    }
    const next = make(op);
    const i = out.findIndex((r) => r.value === op.value);
    if (i < 0) out.push(next);
    else out[i] = next;
  }
  return out;
}

/** 项目权限文件随仓库克隆而来，不可信：只追加，不能放宽保护。 */
function appendProjectOps<T extends { value: string }>(
  rules: T[],
  ops: AddOp[],
  make: (op: AddOp) => T,
): T[] {
  return [...rules, ...ops.map(make)];
}

function stripProjectRemovals(ops: GlobalOp[], layerName: string, errors: BuildError[]): AddOp[] {
  const out: AddOp[] = [];
  for (const op of ops) {
    if (op.type === "remove") {
      errors.push({
        message: `${layerName}: '-${op.value}' 已忽略：项目层只能追加规则，删除规则只能写在全局权限文件`,
        scope: "item",
      });
    } else {
      out.push(op);
    }
  }
  return out;
}

export function buildPolicy(input: {
  globalSource?: string | null;
  projectSource?: string | null;
  home?: string;
  cwd?: string;
  permissionPaths: PermissionPaths;
  parseYaml: YamlParser;
}): BuildPolicyResult {
  const ctx: ExpandCtx = {
    home: input.home ?? homedir(),
    cwd: input.cwd ?? process.cwd(),
  };
  const { permissionPaths, parseYaml } = input;

  let commands: CommandRule[] = [];
  let paths = BUILTIN_PATHS.map((r) =>
    compilePathRule(r.value, r.reason, r.except ?? [], "builtin", BUILTIN_PATH_CONFIG, ctx),
  );
  let default_reason: string | undefined;
  const errors: BuildError[] = [];

  const makeCommand =
    (config: string) =>
    (op: AddOp): CommandRule => ({
      value: op.value,
      match: expandHomeInText(op.value, ctx.home),
      reason: op.reason,
      source: "user",
      config: `${config}#deny_commands`,
    });
  const makePath =
    (config: string) =>
    (op: AddOp): PathRule =>
      compilePathRule(op.value, op.reason, [], "user", `${config}#deny_paths`, ctx);

  const loadLayer = (name: string, source: string | null | undefined): ParsedLayer | null => {
    if (source == null) return null;
    const parsed = parseLayerYaml(source, parseYaml);
    if (!parsed.ok) {
      errors.push({ message: `${name}: ${parsed.error}`, scope: "layer" });
      return null;
    }
    errors.push(...parsed.layer.errors.map((e) => ({ message: `${name}: ${e}`, scope: "item" as const })));
    if (parsed.layer.default_reason !== undefined) default_reason = parsed.layer.default_reason;
    return parsed.layer;
  };

  const globalLayer = loadLayer("全局配置", input.globalSource);
  if (globalLayer) {
    commands = applyGlobalOps(commands, globalLayer.commandOps, makeCommand(permissionPaths.globalPath));
    paths = applyGlobalOps(paths, globalLayer.pathOps, makePath(permissionPaths.globalPath));
  }

  const projectLayer = loadLayer("项目配置", input.projectSource);
  if (projectLayer) {
    commands = appendProjectOps(
      commands,
      stripProjectRemovals(projectLayer.commandOps, "项目配置", errors),
      makeCommand(permissionPaths.projectPath),
    );
    paths = appendProjectOps(
      paths,
      stripProjectRemovals(projectLayer.pathOps, "项目配置", errors),
      makePath(permissionPaths.projectPath),
    );
  }

  return { policy: { default_reason, commands, paths }, errors };
}

function resolveFirstExisting(candidates: string[]): string {
  return candidates.find((candidate) => existsSync(candidate)) ?? candidates[0];
}

export function getPermissionPaths(cwd: string, agentDir: string, configDirName: string): PermissionPaths {
  return {
    globalPath: resolveFirstExisting([
      path.join(agentDir, "permissions.yml"),
      path.join(agentDir, "permissions.yaml"),
    ]),
    projectPath: resolveFirstExisting([
      path.join(cwd, configDirName, "permissions.yml"),
      path.join(cwd, configDirName, "permissions.yaml"),
    ]),
  };
}

function readConfigFile(filePath: string): ReadConfigResult {
  try {
    return { status: "ok", text: readFileSync(filePath, "utf8") };
  } catch (e) {
    const err = e as NodeJS.ErrnoException;
    if (err?.code === "ENOENT") return { status: "missing" };
    return { status: "error", message: e instanceof Error ? e.message : String(e) };
  }
}

export function loadPolicyFromPaths(
  paths: PermissionPaths,
  options: { home: string; cwd: string; parseYaml: YamlParser },
): LoadPolicyResult {
  const failures: LoadFailure[] = [];
  const read = (filePath: string): string | null => {
    const result = readConfigFile(filePath);
    if (result.status === "ok") return result.text;
    if (result.status === "error") failures.push({ path: filePath, message: result.message, scope: "layer" });
    return null;
  };

  const built = buildPolicy({
    globalSource: read(paths.globalPath),
    projectSource: read(paths.projectPath),
    home: options.home,
    cwd: options.cwd,
    permissionPaths: paths,
    parseYaml: options.parseYaml,
  });

  for (const { message, scope } of built.errors) {
    const layerPath = message.startsWith("项目配置:") ? paths.projectPath : paths.globalPath;
    failures.push({ path: layerPath, message: message.slice(message.indexOf(":") + 1).trim(), scope });
  }
  return { policy: built.policy, failures };
}
