#!/usr/bin/env bun
// computer-use — 快照/操作 CLI（Token 极致高效率版）
// 闭环用法：
//   computer-use apps [--recent [N]]                      0. 查最近常用应用与运行状态
//   computer-use open <name|bundle_id>                    1. 开启应用并直接返回窗口 PID/WID
//   computer-use windows                                  2. 找已有窗口（pid + window_id）
//   computer-use snapshot <pid> <wid> [--depth N] [--query Q]  3. 读界面并缓存动作 token
//   computer-use click <pid> <wid> <t<idx>|x y> [action]  4. 单击（x/y 为最近快照 PNG 坐标）
//   computer-use double-click <pid> <wid> <t<idx>|x y>    5. 双击（默认短暂置前自动恢复；驱动后台双击缺激活前奏）
//   computer-use type <pid> <wid> [t<idx>] <text>         6. 输入文本（优先 set_value 毫秒级后台写入）
//   computer-use key <pid> <wid> <key> [mods..]           7. 按键（return/space/escape 等）
//   computer-use scroll <pid> <wid> t<idx> down           8. 滚动
//   computer-use front <pid> <wid>                        9. 显式激活窗口（不移动）
//   computer-use move <pid> <wid> <x> <y> [w] [h]         10. 窗口移动/调整大小
import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const DAEMON = process.env.CUA_DRIVER ?? "cua-driver";
const CACHE_DIR = process.env.COMPUTER_USE_CACHE_DIR ?? join(tmpdir(), "computer-use");
const MEDIA_BIN = process.env.MEDIA_CONTROL_BIN ?? "media-control";

type AxElement = {
  element_token: string;
  element_index?: number;
  parent_index?: number | null;
  role: string;
  label: string | null;
  value: string | null;
  selected: boolean | null;
  enabled: boolean | null;
  frame: { x: number; y: number; w: number; h: number } | null;
  desc?: string;
  actions?: string[];
};

type WindowState = {
  pid: number;
  window_id: number;
  snapshot_id?: string;
  returned_element_count?: number;
  total_element_count?: number;
  elements_complete?: boolean;
  screenshot_file_path?: string;
  screenshot_width?: number;
  screenshot_height?: number;
  window_bounds?: { x: number; y: number; width: number; height: number };
  _note?: string;
  elements: AxElement[];
  tree_markdown?: string;
};

type CachedSnapshot = {
  savedAt: number;
  state: WindowState;
};

const usage = `
computer-use — 快照/操作 CLI（Token 极致高效率版）

闭环用法:
  computer-use apps [--recent [N]]                       0. 列出应用：按最近使用时间排序，显示开启状态
                                                          支持关键词过滤: computer-use apps zed
  computer-use open <name|bundle_id>                     1. 启动应用：若已有窗口直接返回，若冷启动则拉起并返回窗口
  computer-use windows                                   2. 找窗口 (pid + window_id)
  computer-use snapshot <pid> <wid> [选项]                3. 读界面：默认浅层扫描并输出窗口视口内元素
                                                          --depth <N>   遍历深度（默认 3）
                                                          --max-elements <N> 元素预算（默认 300）
                                                          --query <str> 仅过滤返回内容，不降低 AX 遍历成本
                                                          --screenshot <path> 保存 PNG（建议 $TMPDIR），像素操作从该图取坐标
                                                          --all         输出全部缓存元素（含滚出视口节点）
                                                          --json        原始 JSON
  computer-use click <pid> <wid> <t<idx>|x y> [action]   4. 单击：t<idx> 复用最近快照；x/y 必须是 PNG 像素坐标
                                                          可选验证: --wait <t<idx>|media:playing|media:paused> [--timeout <ms>]
  computer-use double-click <pid> <wid> <t<idx>|x y>     5. 双击：打开/播放列表项；默认短暂置前并自动恢复原前台，
                                                          无需 --foreground（驱动后台双击缺 no-raise 激活，非前台会被忽略）
  computer-use type <pid> <wid> [t<idx>] <text>          6. 输入文本：写入指定元素或当前焦点控件；支持 --wait
  computer-use key <pid> <wid> [t<idx>] <key> [mods..] 7. 按键，如: computer-use key 16881 3399 space
                                                          支持指定目标控件后台聚焦按键，如: key 75797 3735 t4 return；支持 --wait
                                                          修饰符: cmd shift option ctrl fn
  computer-use scroll <pid> <wid> t<idx> down [line|page]8. 按元素滚动；支持 --foreground
  computer-use front <pid> <wid>                         9. 显式激活窗口，不自动移动
  computer-use move <pid> <wid> <x> <y> [w] [h]          10. 移动窗口或调整大小
  computer-use help | -h                                 本帮助

要点:
  - 默认后台 AX 操作，不抢焦点、不切工作区、不移动窗口；front/--foreground 是明确的最后手段
  - t<idx> 绑定最近一次 snapshot 并直接复用，不会为动作重复扫描 AX 树
  - 可选 --wait <t<idx>> 差分验证目标属性改变；或 --wait media:playing 显式按需验证系统媒体状态
  - 输出的 ax=(x,y) 是辅助定位的屏幕点，不可用于像素点击；像素 x/y 必须读取 --screenshot 生成的 PNG
  - query 只减少返回内容和 Token，不改变驱动遍历成本；大树应降低 depth/max-elements 或改用截图
  - effect=unverifiable 只表示已投递，必须从后续状态变化验证结果
`.trim();

function call(tool: string, args: object): string {
  return execFileSync(DAEMON, ["call", tool, JSON.stringify(args)], { encoding: "utf8" });
}

function snapshotCachePath(pid: number, wid: number): string {
  return join(CACHE_DIR, `${pid}-${wid}.json`);
}

function saveSnapshot(state: WindowState): void {
  mkdirSync(CACHE_DIR, { recursive: true });
  writeFileSync(snapshotCachePath(state.pid, state.window_id), JSON.stringify({ savedAt: Date.now(), state }), {
    mode: 0o600,
  });
}

function loadSnapshot(pid: number, wid: number): CachedSnapshot {
  let cached: CachedSnapshot;
  try {
    cached = JSON.parse(readFileSync(snapshotCachePath(pid, wid), "utf8"));
  } catch {
    console.error(`error: 找不到 ${pid}:${wid} 的快照缓存，请先运行 'computer-use snapshot ${pid} ${wid}'`);
    process.exit(1);
  }
  if (cached.state.pid !== pid || cached.state.window_id !== wid || !Array.isArray(cached.state.elements)) {
    console.error(`error: ${pid}:${wid} 的快照缓存无效，请重新运行 snapshot`);
    process.exit(1);
  }
  return cached;
}

function timeAgo(dateMs: number): string {
  const diffSec = Math.max(0, Math.floor((Date.now() - dateMs) / 1000));
  if (diffSec < 60) return `${diffSec}秒前`;
  if (diffSec < 3600) return `${Math.floor(diffSec / 60)}分钟前`;
  if (diffSec < 86400) return `${Math.floor(diffSec / 60)}小时前`;
  return `${Math.floor(diffSec / 86400)}天前`;
}

function cmdApps(query?: string, limitStr?: string): void {
  const runningMap = new Map<string, { pid: number; bid: string; name: string; isForeground: boolean }>();
  try {
    const lsOutput = execFileSync("lsappinfo", ["list"], { encoding: "utf8" });
    const blocks = lsOutput.split(/\n(?=\d+\)\s*")/);
    for (const block of blocks) {
      const nameMatch = block.match(/^\d+\)\s*"([^"]+)"/);
      const bidMatch = block.match(/bundleID="([^"]+)"/);
      const pidMatch = block.match(/pid\s*=\s*(\d+)/);
      const typeMatch = block.match(/type="([^"]+)"/);
      if (pidMatch && (nameMatch || bidMatch)) {
        const pid = Number(pidMatch[1]);
        const name = nameMatch ? nameMatch[1] : "";
        const bid = bidMatch ? bidMatch[1] : "";
        const isForeground = typeMatch ? typeMatch[1] === "Foreground" : false;
        const item = { pid, bid, name, isForeground };
        if (name) runningMap.set(name.toLowerCase(), item);
        if (bid) runningMap.set(bid.toLowerCase(), item);
      }
    }
  } catch {}

  let rawPaths = "";
  try {
    rawPaths = execFileSync(
      "mdfind",
      [
        'kMDItemContentType == "com.apple.application-bundle" && kMDItemLastUsedDate >= $time.now(-30d)',
        "-onlyin",
        "/Applications",
        "-onlyin",
        "/System/Applications",
        "-onlyin",
        `${process.env.HOME}/Applications`,
      ],
      { encoding: "utf8" },
    );
  } catch {}

  const paths = rawPaths.trim().split("\n").filter(Boolean);
  const appList: Array<{
    name: string;
    bundleId: string;
    path: string;
    lastUsedMs: number;
    running: boolean;
    pid: number;
  }> = [];

  if (paths.length > 0) {
    try {
      const mdlsOut = execFileSync(
        "mdls",
        ["-name", "kMDItemLastUsedDate", "-name", "kMDItemCFBundleIdentifier", ...paths],
        { encoding: "utf8", maxBuffer: 10 * 1024 * 1024 },
      );
      const idMatches = [...mdlsOut.matchAll(/kMDItemCFBundleIdentifier\s*=\s*(.*)/g)].map((m) =>
        m[1].trim().replace(/^"|"$/g, ""),
      );
      const dateMatches = [...mdlsOut.matchAll(/kMDItemLastUsedDate\s*=\s*(.*)/g)].map((m) => m[1].trim());

      for (let i = 0; i < paths.length; i++) {
        const p = paths[i];
        const name = p.split("/").pop()?.replace(/\.app$/, "") ?? "";
        const bId = idMatches[i] && idMatches[i] !== "(null)" ? idMatches[i] : "";
        const dateStr = dateMatches[i] && dateMatches[i] !== "(null)" ? dateMatches[i] : "";
        const lastUsedMs = dateStr ? new Date(dateStr).getTime() : 0;

        const runInfo = runningMap.get(name.toLowerCase()) || (bId ? runningMap.get(bId.toLowerCase()) : null);
        appList.push({
          name,
          bundleId: bId,
          path: p,
          lastUsedMs,
          running: Boolean(runInfo),
          pid: runInfo ? runInfo.pid : 0,
        });
      }
    } catch {}
  }

  appList.sort((a, b) => b.lastUsedMs - a.lastUsedMs);

  let filtered = appList;
  if (query && query !== "--recent") {
    const q = query.toLowerCase();
    filtered = appList.filter((a) => a.name.toLowerCase().includes(q) || a.bundleId.toLowerCase().includes(q));
  }

  const limit = Number(limitStr) > 0 ? Number(limitStr) : 15;
  const sliced = filtered.slice(0, limit);

  console.log("状态\tPID\t应用名称\tBundle ID\t最近使用");
  for (const a of sliced) {
    const status = a.running ? "🟢 开启中" : "⚪️ 未开启";
    const pidStr = a.pid > 0 ? String(a.pid) : "-";
    const ago = a.lastUsedMs > 0 ? timeAgo(a.lastUsedMs) : "较早之前";
    console.log(`${status}\t${pidStr}\t${a.name}\t${a.bundleId || "-"}\t${ago}`);
  }
}

function cmdOpen(target: string): void {
  if (!target) {
    console.error("error: 请提供应用名称或 bundle_id，例如: computer-use open Zed");
    process.exit(1);
  }

  const tree = JSON.parse(call("get_accessibility_tree", {}));
  const targetLower = target.toLowerCase();
  const existingWin = tree.windows?.find((w: { app_name?: string }) =>
    w.app_name?.toLowerCase().includes(targetLower),
  );

  if (existingWin) {
    console.log(`已在运行: ${existingWin.app_name} (pid=${existingWin.pid}, window_id=${existingWin.window_id})`);
    console.log(`直接读取界面: computer-use snapshot ${existingWin.pid} ${existingWin.window_id}`);
    return;
  }

  const isBundle = target.includes(".");
  const launchArgs = isBundle ? { bundle_id: target } : { name: target };
  const resp = JSON.parse(call("launch_app", launchArgs));

  const pid = resp.pid;
  const name = resp.name ?? target;
  console.log(`已拉起应用: ${name} (pid=${pid})`);

  let readyWin = resp.windows?.[0];
  if (!readyWin) {
    for (let i = 0; i < 10; i++) {
      execFileSync("sleep", ["0.5"]);
      try {
        const freshTree = JSON.parse(call("get_accessibility_tree", {}));
        readyWin = freshTree.windows?.find((w: { pid?: number }) => w.pid === pid);
        if (readyWin) break;
      } catch {}
    }
  }

  if (readyWin) {
    console.log(`窗口就绪: window_id=${readyWin.window_id}, title="${readyWin.title ?? ""}"`);
    console.log(`立即读取界面: computer-use snapshot ${pid} ${readyWin.window_id}`);
  } else {
    console.log(`应用已启动 (pid=${pid})，窗口正在初始化中。`);
    console.log(`稍后查询窗口: computer-use windows`);
  }
}

function cmdWindows(): void {
  const tree = JSON.parse(call("get_accessibility_tree", {}));
  console.log("PID\tWINDOW_ID\tAPP\tTITLE");
  for (const w of tree.windows) {
    console.log([w.pid, w.window_id, w.app_name, w.title].join("\t"));
  }
}

type FetchOptions = {
  depth?: number;
  query?: string;
  maxElements?: number;
  screenshotFile?: string;
};

function fetchState(pid: number, wid: number, opts?: FetchOptions): WindowState {
  const reqArgs: Record<string, unknown> = {
    pid,
    window_id: wid,
    include_screenshot: false,
    max_depth: opts?.depth ?? 3,
    max_elements: opts?.maxElements ?? 300,
  };
  if (opts?.query) reqArgs.query = opts.query;
  if (opts?.screenshotFile) reqArgs.screenshot_out_file = opts.screenshotFile;

  let out: string;
  try {
    out = call("get_window_state", reqArgs);
  } catch (e) {
    const err = e as { stderr?: unknown; stdout?: unknown; message?: string };
    const msg = String(err.stderr || err.stdout || err.message || "").trim();
    console.error(`error: get_window_state failed for pid=${pid} window=${wid}${msg ? ` — ${msg}` : ""}`);
    process.exit(1);
  }

  let resp: WindowState;
  try {
    resp = JSON.parse(out) as WindowState;
  } catch {
    console.error(`error: get_window_state returned non-JSON:\n${out.trim()}`);
    process.exit(1);
  }

  if (!Array.isArray(resp.elements)) {
    console.error(JSON.stringify(resp, null, 2));
    process.exit(1);
  }

  // 从 tree_markdown 补充 description 与 actions 语义（消除 P/S/s 等单字母语义歧义）
  if (resp.tree_markdown && resp.elements.length > 0) {
    const metaMap = new Map<number, { desc?: string; actions?: string[] }>();
    for (const line of resp.tree_markdown.split("\n")) {
      const m = line.match(/^\s*-\s*\[(\d+)\]\s+AX\w+(?:.*?\(([^)]+)\))?(?:.*?actions=\[([^\]]*)\])?/);
      if (m) {
        const idx = Number(m[1]);
        const desc = m[2]?.trim();
        const actions = m[3] ? m[3].split(",").map((s) => s.trim()) : undefined;
        metaMap.set(idx, { desc, actions });
      }
    }
    for (const el of resp.elements) {
      if (el.element_index !== undefined) {
        const meta = metaMap.get(el.element_index);
        if (meta?.desc) el.desc = meta.desc;
        if (meta?.actions) el.actions = meta.actions;
      }
    }
  }

  return resp;
}

function resolveElement(pid: number, wid: number, tIdx: string): AxElement {
  const m = /^t(\d+)$/.exec(tIdx);
  if (!m) {
    console.error(`error: 元素应为 t<idx> 形式（如 t54），先用 'computer-use snapshot' 查询`);
    process.exit(1);
  }
  const cached = loadSnapshot(pid, wid);
  const el = cached.state.elements.find((e) => e.element_index === Number(m[1]));
  if (!el) {
    console.error(`error: index ${m[1]} 不在最近快照内，请重新运行 snapshot`);
    process.exit(1);
  }
  const snapshotId = cached.state.snapshot_id ?? el.element_token.split(":")[0];
  const label = (el.label ?? el.desc ?? "").replace(/[\t\n]/g, " ");
  console.log(`target: snapshot=${snapshotId} age=${Date.now() - cached.savedAt}ms ${tIdx} ${el.role} ${label}`);
  return el;
}

function cmdSnapshot(
  pid: number,
  wid: number,
  raw: boolean,
  showAll: boolean,
  depth?: number,
  query?: string,
  maxElements?: number,
  screenshotFile?: string,
): void {
  const resp = fetchState(pid, wid, { depth, query, maxElements, screenshotFile });
  saveSnapshot(resp);
  if (raw) {
    console.log(JSON.stringify(resp));
    return;
  }
  const sess = resp.elements[0]?.element_token.split(":")[0] ?? "?";
  const firstLabel = resp.elements[0]?.label ?? "";

  const win = resp.elements.find((e) => e.role === "AXWindow");
  const wf = win?.frame;

  // 几何相交判定：完全在窗口可视范围外的缓存元素，判定为不可见
  const elements = showAll || Boolean(query)
    ? resp.elements
    : resp.elements.filter((e) => {
        if (e.role.startsWith("AXMenu")) return false;
        if (!e.frame) return false;
        if (!wf) return true;
        const f = e.frame;
        return !(
          f.x + (f.w ?? 0) <= wf.x ||
          f.x >= wf.x + wf.w ||
          f.y + (f.h ?? 0) <= wf.y ||
          f.y >= wf.y + wf.h
        );
      });

  const childrenMap = new Map<number, AxElement[]>();
  for (const e of resp.elements) {
    if (e.parent_index !== undefined && e.parent_index !== null) {
      const list = childrenMap.get(e.parent_index) ?? [];
      list.push(e);
      childrenMap.set(e.parent_index, list);
    }
  }

  const returned = resp.returned_element_count ?? resp.elements.length;
  const total = resp.total_element_count ?? returned;
  const completeness = resp.elements_complete === false ? "truncated" : "complete";
  console.log(
    `snapshot=${resp.snapshot_id ?? sess} state=${completeness} viewport=${elements.length} returned=${returned} total=${total}${firstLabel ? ` app=${firstLabel}` : ""} target=${pid}:${wid}`,
  );
  if (resp._note) console.log(`note=${resp._note.replace(/\s+/g, " ").trim()}`);
  if (resp.screenshot_file_path) {
    console.log(
      `screenshot=${resp.screenshot_file_path} size=${resp.screenshot_width ?? "?"}x${resp.screenshot_height ?? "?"} coordinates=png-pixels`,
    );
  }

  const rows = elements.map((e) => {
    const f = e.frame;
    const isOut = Boolean(
      f &&
      wf &&
      (f.y + (f.h ?? 0) < wf.y || f.y > wf.y + wf.h ||
       f.x + (f.w ?? 0) < wf.x || f.x > wf.x + wf.w)
    );

    let label = (e.label ?? e.value ?? "").replace(/[\t\n]/g, " ").trim();
    // 注入 desc 消除仅由单个字符表达的按钮含义 (如 P -> Play/Pause playback)
    if (e.desc && label.toLowerCase() !== e.desc.toLowerCase()) {
      label = label ? `${label} (${e.desc})` : `(${e.desc})`;
    }

    // 若当前为 Row 且无 label，反向聚合子元素文本
    if (!label && e.role === "AXRow") {
      const kids = childrenMap.get(e.element_index!) ?? [];
      const kidText = kids
        .map((k) => (k.label ?? k.value ?? k.desc ?? "").trim())
        .filter(Boolean)
        .join(" ");
      if (kidText) label = `[${kidText}]`;
    }

    return {
      idx: e.element_token.split(":")[1],
      role: e.role.replace(/^AX/, ""),
      label,
      x: f?.x ?? null,
      y: f?.y ?? null,
      sel: e.selected === true,
      en: e.enabled === true,
      out: isOut,
    };
  });

  rows.sort((a, b) => {
    if (a.x === null && b.x !== null) return 1;
    if (a.x !== null && b.x === null) return -1;
    if (a.y === null || b.y === null) return 0;
    return a.y - b.y || a.x - b.x;
  });

  for (const r of rows) {
    const coord = r.x === null ? "ax=none" : `ax=(${Math.floor(r.x)},${Math.floor(r.y)})`;
    const flags = [r.sel && "sel", r.en && "on", r.out && "out"].filter(Boolean).join(",");
    console.log(`t${r.idx}\t${r.role}\t${r.label}\t${coord}\t${flags}`);
  }
}

function act(tool: string, args: Record<string, unknown>): void {
  let raw = "";
  let r: {
    effect?: string;
    route?: string;
    path?: string;
    code?: string;
    delivered_chars?: number;
    requested_chars?: number;
    retry_from_character?: number;
    retryable?: boolean;
    delivery?: { mode?: string };
    evidence?: Array<{ kind?: string }>;
    refusal?: { code?: string; message?: string };
  };
  try {
    raw = call(tool, args);
    r = JSON.parse(raw);
  } catch (e) {
    const err = e as { stderr?: unknown; stdout?: unknown; message?: string };
    const msg = raw.trim() || String(err.stderr || err.stdout || err.message || "").trim();
    console.error(`error: ${tool} failed${msg ? ` — ${msg}` : ""}`);
    process.exit(1);
  }
  const evidence = r.evidence?.map((item) => item.kind).filter(Boolean).join(",") || "none";
  const chars =
    r.delivered_chars === undefined || r.requested_chars === undefined
      ? ""
      : ` chars=${r.delivered_chars}/${r.requested_chars}`;
  console.log(
    `${tool}: effect=${r.effect ?? "unknown"} route=${r.route ?? r.path ?? "unknown"} delivery=${r.delivery?.mode ?? "unknown"} evidence=${evidence}${r.code ? ` code=${r.code}` : ""}${chars}${r.retryable === undefined ? "" : ` retryable=${r.retryable}`}${r.retry_from_character === undefined ? "" : ` retry_from=${r.retry_from_character}`}${r.refusal?.code ? ` refusal=${r.refusal.code}` : ""}`,
  );
  if (r.refusal?.message) console.log(`message=${r.refusal.message.replace(/\s+/g, " ").trim()}`);
  const state =
    r.effect === "confirmed"
      ? "confirmed"
      : r.effect === "unverifiable"
        ? "delivered_unverified"
        : r.effect === "partial"
          ? "partial"
          : r.refusal
            ? "refused"
            : "unknown";
  console.log(
    `state=${state}${state === "confirmed" ? "" : ` next='computer-use snapshot ${args.pid} ${args.window_id}'`}`,
  );
}

function cmdFront(pid: number, wid?: number): void {
  const args = wid === undefined ? { pid } : { pid, window_id: wid };
  act("bring_to_front", args);
}

function cmdMove(pid: number, wid: number, x: number, y: number, w?: number, h?: number): void {
  let targetW = w;
  let targetH = h;
  if (!targetW || !targetH) {
    try {
      const winList = JSON.parse(call("list_windows", {}));
      const win = winList.windows?.find((item: { pid: number; window_id: number }) =>
        item.pid === pid && item.window_id === wid,
      );
      if (win?.bounds) {
        targetW = targetW ?? win.bounds.width;
        targetH = targetH ?? win.bounds.height;
      }
    } catch {}
  }
  act("set_window_frame", {
    pid,
    window_id: wid,
    x,
    y,
    width: targetW ?? 1000,
    height: targetH ?? 700,
  });
}

function requirePixelSnapshot(pid: number, wid: number): void {
  const cached = loadSnapshot(pid, wid);
  if (!cached.state.screenshot_file_path) {
    console.error(
      `error: 像素坐标必须来自最近快照 PNG，请先运行 'computer-use snapshot ${pid} ${wid} --screenshot <path>'`,
    );
    process.exit(1);
  }
  console.log(
    `target: snapshot=${cached.state.snapshot_id ?? "unknown"} age=${Date.now() - cached.savedAt}ms screenshot=${cached.state.screenshot_width ?? "?"}x${cached.state.screenshot_height ?? "?"}`,
  );
}

function extractWaitOptions(args: string[]): {
  cleanArgs: string[];
  waitTarget?: string;
  timeoutMs: number;
} {
  const cleanArgs: string[] = [];
  let waitTarget: string | undefined;
  let timeoutMs = 2000;

  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--wait") {
      waitTarget = args[++i];
    } else if (args[i] === "--timeout") {
      timeoutMs = Number(args[++i]) || 2000;
    } else {
      cleanArgs.push(args[i]);
    }
  }
  return { cleanArgs, waitTarget, timeoutMs };
}

function readMediaStatus(): { ok: boolean; playing?: boolean; title?: string; artist?: string } {
  try {
    const raw = execFileSync(MEDIA_BIN, ["get", "--now", "--no-artwork"], {
      encoding: "utf8",
      timeout: 1500,
    });
    const info = JSON.parse(raw);
    if (!info) return { ok: false };
    return { ok: true, playing: Boolean(info.playing), title: info.title, artist: info.artist };
  } catch {
    return { ok: false };
  }
}

function getElementSignature(pid: number, wid: number, target: string): string {
  const m = /^t(\d+)(?::(.*))?$/.exec(target);
  if (!m) return "";
  const targetIdx = Number(m[1]);
  const cached = loadSnapshot(pid, wid);
  const el = cached.state.elements.find((e) => e.element_index === targetIdx);
  if (!el) return "";
  const sub = m[2];
  if (sub === "sel") return String(Boolean(el.selected));
  if (sub === "val") return String(el.value ?? "");
  return `${el.value ?? ""}|${Boolean(el.selected)}|${el.label ?? ""}`;
}

function prepareWait(pid: number, wid: number, target?: string): string {
  if (!target || target.startsWith("media:")) return "";
  return getElementSignature(pid, wid, target);
}

function finishWait(
  pid: number,
  wid: number,
  target: string,
  beforeSig: string,
  timeoutMs = 2000,
): void {
  const start = performance.now();

  if (target.startsWith("media:")) {
    const expectedPlaying = target === "media:playing";
    let ok = false;
    let currentStatus: ReturnType<typeof readMediaStatus> = { ok: false };

    while (performance.now() - start < timeoutMs) {
      currentStatus = readMediaStatus();
      if (currentStatus.ok && currentStatus.playing === expectedPlaying) {
        ok = true;
        break;
      }
      execFileSync("sleep", ["0.15"]);
    }
    const elapsed = Math.round(performance.now() - start);
    const mediaTitle = currentStatus.title ? ` title="${currentStatus.title}"` : "";
    console.log(
      `verify: target=${target} verdict=${ok ? "confirmed" : "timeout"} state=${currentStatus.playing ? "playing" : "paused"}${mediaTitle} elapsed=${elapsed}ms`,
    );
    if (!ok) process.exit(2);
    return;
  }

  const m = /^t(\d+)(?::(.*))?$/.exec(target);
  if (!m) {
    console.error(`error: 无效的 --wait 目标 '${target}'，应为 t<idx> (如 t45) 或 media:playing|media:paused`);
    process.exit(1);
  }
  const targetIdx = Number(m[1]);
  const sub = m[2];
  let ok = false;
  let afterSig = beforeSig;

  while (performance.now() - start < timeoutMs) {
    execFileSync("sleep", ["0.15"]);
    try {
      const fresh = fetchState(pid, wid, { depth: 3, maxElements: 300 });
      const targetEl = fresh.elements.find((e) => e.element_index === targetIdx);
      if (targetEl) {
        if (sub === "sel") {
          afterSig = String(Boolean(targetEl.selected));
        } else if (sub === "val") {
          afterSig = String(targetEl.value ?? "");
        } else {
          afterSig = `${targetEl.value ?? ""}|${Boolean(targetEl.selected)}|${targetEl.label ?? ""}`;
        }
        if (afterSig !== beforeSig) {
          saveSnapshot(fresh);
          ok = true;
          break;
        }
      }
    } catch {}
  }

  const elapsed = Math.round(performance.now() - start);
  console.log(
    `verify: target=${target} verdict=${ok ? "confirmed" : "timeout"} diff="${beforeSig}"->"${afterSig}" elapsed=${elapsed}ms`,
  );
  if (!ok) process.exit(2);
}

function withWait(
  pid: number,
  wid: number,
  args: string[],
  actionFn: (cleanArgs: string[]) => void,
): void {
  const { cleanArgs, waitTarget, timeoutMs } = extractWaitOptions(args);
  const beforeSig = prepareWait(pid, wid, waitTarget);
  actionFn(cleanArgs);
  if (waitTarget) {
    finishWait(pid, wid, waitTarget, beforeSig, timeoutMs);
  }
}

function cmdClick(pid: number, wid: number, rest: string[]): void {
  const isForeground = rest.includes("--foreground");
  const filtered = rest.filter((arg) => arg !== "--foreground");

  // 模式 1: PNG 像素坐标点击: computer-use click <pid> <wid> <x> <y> [--foreground]
  const x = Number(filtered[0]);
  const y = Number(filtered[1]);
  if (!Number.isNaN(x) && !Number.isNaN(y) && !filtered[0].startsWith("t")) {
    requirePixelSnapshot(pid, wid);
    const args: Record<string, unknown> = { pid, window_id: wid, x, y };
    if (isForeground) args.delivery_mode = "foreground";
    act("click", args);
    return;
  }

  // 模式 2: 元素 Token 点击: computer-use click <pid> <wid> t<idx> [action] [--foreground]
  const tIdx = filtered[0];
  const customAction = filtered[1];
  const el = resolveElement(pid, wid, tIdx);

  // 智能 Action 决策:
  // 若元素为 AXTextField 且未指定 action，自动选用 confirm（避免 press 产生 -25206）
  let actionToUse = customAction ?? "press";
  if (!customAction && el.role === "AXTextField") {
    actionToUse = el.actions?.includes("confirm") ? "confirm" : "press";
  }

  const clickArgs: Record<string, unknown> = {
    pid,
    window_id: wid,
    element_token: el.element_token,
    action: actionToUse,
  };
  if (isForeground) clickArgs.delivery_mode = "foreground";
  act("click", clickArgs);
}

function cmdDoubleClick(pid: number, wid: number, rest: string[]): void {
  // 双击默认走 foreground 交付:驱动会短暂置前目标窗口 → 双击 → 自动恢复原前台。
  // 原因:cua-driver 后台双击路径缺少 no-raise 激活前奏(单击在 1fbcacf6f 已补,双击漏了),
  // 非前台 AppKit 窗口的双击会被静默忽略(Audirvana 列表实测:后台双击无效)。
  // 上游关联: https://github.com/trycua/cua/issues/2206 (foreground 交付 = 动作级激活 + 保证恢复的审计)
  // 保留 --foreground 仅为命令行兼容:参数在尾部,不影响下方坐标/token 解析。
  const x = Number(rest[0]);
  const y = Number(rest[1]);
  if (!Number.isNaN(x) && !Number.isNaN(y) && !rest[0].startsWith("t")) {
    requirePixelSnapshot(pid, wid);
    act("double_click", { pid, window_id: wid, x, y, delivery_mode: "foreground" });
    return;
  }

  const el = resolveElement(pid, wid, rest[0]);
  act("double_click", {
    pid,
    window_id: wid,
    element_token: el.element_token,
    delivery_mode: "foreground",
  });
}

function cmdType(pid: number, wid: number, rest: string[]): void {
  const isForeground = rest.includes("--foreground");
  const filtered = rest.filter((arg) => arg !== "--foreground");

  // 若提供了 t<idx>: computer-use type <pid> <wid> t5 "text"
  if (filtered[0]?.startsWith("t")) {
    const tIdx = filtered[0];
    const text = filtered.slice(1).join(" ");
    const el = resolveElement(pid, wid, tIdx);

    // 优先尝试 set_value: 原生 Cocoa 文本框毫秒级后台直写并带有 value_readback 强验证
    try {
      const svResult = JSON.parse(
        call("set_value", { pid, window_id: wid, element_token: el.element_token, value: text }),
      );
      if (svResult.effect === "confirmed") {
        console.log(`set_value: effect=confirmed (value_readback verified)`);
        console.log(`验证: computer-use snapshot ${pid} ${wid} 查看文本写入结果`);
        return;
      }
    } catch {}

    // 降级为 type_text
    const args: Record<string, unknown> = {
      pid,
      window_id: wid,
      element_token: el.element_token,
      text,
    };
    if (isForeground) args.delivery_mode = "foreground";
    act("type_text", args);
    return;
  }

  // 直接针对当前焦点输入: computer-use type <pid> <wid> "text"
  const text = filtered.join(" ");
  const args: Record<string, unknown> = { pid, window_id: wid, text };
  if (isForeground) args.delivery_mode = "foreground";
  act("type_text", args);
}

function cmdScroll(pid: number, wid: number, tIdx: string, dir: string, by: string, foreground: boolean): void {
  if (!["up", "down", "left", "right"].includes(dir)) {
    console.error(`error: direction 应为 up/down/left/right`);
    process.exit(1);
  }
  const el = resolveElement(pid, wid, tIdx);
  const args: Record<string, unknown> = { pid, window_id: wid, element_token: el.element_token, direction: dir, by };
  if (foreground) args.delivery_mode = "foreground";
  act("scroll", args);
}

function cmdKey(pid: number, wid: number, rest: string[]): void {
  const isForeground = rest.includes("--foreground");
  const filtered = rest.filter((m) => m !== "--foreground");

  let elementToken: string | undefined;
  let key: string;
  let mods: string[];

  if (filtered[0]?.startsWith("t") && /^t\d+$/.test(filtered[0])) {
    const el = resolveElement(pid, wid, filtered[0]);
    elementToken = el.element_token;
    key = filtered[1];
    mods = filtered.slice(2);
  } else {
    key = filtered[0];
    mods = filtered.slice(1);
  }

  if (!key) {
    console.error("error: 请提供要按下的按键名称，例如: return, space, escape, l cmd");
    process.exit(1);
  }

  const args: Record<string, unknown> = { pid, window_id: wid, key };
  if (elementToken) args.element_token = elementToken;
  if (mods.length) args.modifiers = mods;
  if (isForeground) args.delivery_mode = "foreground";
  act("press_key", args);
}

function pair(rest: string[]): [number, number] {
  const pid = Number(rest[0]);
  const wid = Number(rest[1]);
  if (!Number.isInteger(pid) || !Number.isInteger(wid)) {
    console.error(`error: pid 和 window_id 必须是整数，先用 'computer-use windows' 查询`);
    process.exit(1);
  }
  return [pid, wid];
}

const startTime = performance.now();
let timingPrinted = false;

function printTiming(): void {
  if (!timingPrinted && !process.argv.includes("--json")) {
    timingPrinted = true;
    const durationMs = Math.round(performance.now() - startTime);
    console.log(`\nduration_ms=${durationMs}`);
  }
}

process.on("exit", printTiming);

try {
  const [cmd, ...rest] = process.argv.slice(2);
  switch (cmd) {
    case "apps":
      {
        const isRecent = rest[0] === "--recent";
        const query = isRecent ? undefined : rest[0];
        const limit = isRecent ? rest[1] : rest[1];
        cmdApps(query, limit);
      }
      break;
    case "open":
      cmdOpen(rest[0]);
      break;
    case "windows":
      cmdWindows();
      break;
    case "snapshot":
      {
        const [pid, wid] = pair(rest);
        const args = rest.slice(2);
        const isRaw = args.includes("--json");
        const showAll = args.includes("--all");

        let depth: number | undefined;
        const dIdx = args.indexOf("--depth");
        if (dIdx !== -1 && args[dIdx + 1]) depth = Number(args[dIdx + 1]);

        let query: string | undefined;
        const qIdx = args.indexOf("--query");
        if (qIdx !== -1 && args[qIdx + 1]) query = args[qIdx + 1];

        let maxElements: number | undefined;
        const mIdx = args.indexOf("--max-elements");
        if (mIdx !== -1 && args[mIdx + 1]) maxElements = Number(args[mIdx + 1]);

        let screenshotFile: string | undefined;
        const sIdx = args.indexOf("--screenshot");
        if (sIdx !== -1 && args[sIdx + 1]) screenshotFile = args[sIdx + 1];

        cmdSnapshot(pid, wid, isRaw, showAll, depth, query, maxElements, screenshotFile);
      }
      break;
    case "help":
    case "-h":
    case "--help":
      console.log(usage);
      break;
    case "click":
      {
        const [pid, wid] = pair(rest);
        withWait(pid, wid, rest.slice(2), (clean) => cmdClick(pid, wid, clean));
      }
      break;
    case "double-click":
    case "dblclick":
      {
        const [pid, wid] = pair(rest);
        withWait(pid, wid, rest.slice(2), (clean) => cmdDoubleClick(pid, wid, clean));
      }
      break;
    case "type":
      {
        const [pid, wid] = pair(rest);
        withWait(pid, wid, rest.slice(2), (clean) => cmdType(pid, wid, clean));
      }
      break;
    case "scroll":
      {
        const [pid, wid] = pair(rest);
        const scrollArgs = rest.slice(4);
        const by = scrollArgs.find((arg) => arg !== "--foreground") ?? "line";
        cmdScroll(pid, wid, rest[2], rest[3], by, scrollArgs.includes("--foreground"));
      }
      break;
    case "key":
      {
        const [pid, wid] = pair(rest);
        withWait(pid, wid, rest.slice(2), (clean) => cmdKey(pid, wid, clean));
      }
      break;
    case "front":
      {
        const [pid, wid] = pair(rest);
        cmdFront(pid, wid);
      }
      break;
    case "move":
      {
        const [pid, wid] = pair(rest);
        const x = Number(rest[2]);
        const y = Number(rest[3]);
        const w = rest[4] ? Number(rest[4]) : undefined;
        const h = rest[5] ? Number(rest[5]) : undefined;
        cmdMove(pid, wid, x, y, w, h);
      }
      break;
    default:
      console.error(`error: unknown subcommand '${cmd ?? ""}'`);
      console.log(usage);
      process.exit(1);
  }
} finally {
  printTiming();
}
