#!/usr/bin/env bun
// computer-use — 窗口快照与自动化操作 CLI
// 核心架构：AutomationSession 统一内聚动作执行、后置观察、快照缓存刷新与等待校验。
import { execFileSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, readFileSync, realpathSync, renameSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, join } from "node:path";

// ---------------------------------------------------------------------------
// 领域实体与类型
// ---------------------------------------------------------------------------

export type AxElement = {
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

export type Rect = { x: number; y: number; width: number; height: number };

export type WindowState = {
  pid: number;
  window_id: number;
  snapshot_id?: string;
  screenshot_file_path?: string;
  screenshot_width?: number;
  screenshot_height?: number;
  // 驱动按 screenshot_scale 倍窗口点数抓原生像素,再把交给我们的 PNG 压到 max_image_dimension。
  // 两个空间的换算比只能由这两个数实算;frame_valid 为 false 时驱动自己说这个变换无法证明。
  screenshot_scale?: number;
  screenshot_frame_valid?: boolean;
  window_bounds?: Rect;
  // PNG 是哪个窗口几何下拍的。窗口被挪动后这组像素坐标就已失效，必须能判出来。
  screenshot_bounds?: Rect;
  // 驱动逐条报告每种投递路由此刻是否可用，是判断「为什么动作落不下去」的权威来源。
  background_input?: {
    exact_window?: { status?: string };
    routes?: Array<{ route?: string; status?: string; reason?: string }>;
  };
  _note?: string;
  elements: AxElement[];
  tree_markdown?: string;
};

export type WindowRecord = {
  pid: number;
  window_id: number;
  app_name?: string;
  title?: string;
  bounds?: Rect;
  z_index?: number | null;
  is_on_screen?: boolean;
  on_current_space?: boolean;
  space_ids?: number[];
  current_space_id?: number | null;
};

export type ElementTarget = { kind: "element"; token: string };
export type PixelTarget = { kind: "pixel"; x: number; y: number; fromZoom?: boolean };

export type AutomationAction =
  | { kind: "click"; target: ElementTarget | PixelTarget; action?: string; foreground?: boolean }
  | { kind: "right-click"; target: ElementTarget | PixelTarget; foreground?: boolean }
  | { kind: "double-click"; target: ElementTarget | PixelTarget }
  | { kind: "drag"; fromX: number; fromY: number; toX: number; toY: number; foreground?: boolean }
  | { kind: "type"; target?: ElementTarget; text: string; foreground?: boolean }
  | { kind: "key"; target?: ElementTarget; key: string; modifiers?: string[]; foreground?: boolean }
  | { kind: "scroll"; target: ElementTarget; direction: "up" | "down" | "left" | "right"; by: string; foreground?: boolean }
  | { kind: "front" }
  | { kind: "move"; x: number; y: number; width?: number; height?: number };

export type TargetResolution =
  | { kind: "element"; snapshotId: string; ageMs: number; token: string; role: string; label: string; unqualified?: boolean; note?: string }
  | { kind: "pixel"; snapshotId: string; ageMs: number; screenshotWidth?: number; screenshotHeight?: number; note?: string };

export type DeliveryResponse = {
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

export type Delivery = {
  tool: string;
  response: DeliveryResponse;
  setValueReadback?: boolean;
  // 驱动 hotkey 不认 element_token，指向文本控件时必须先把焦点点上去。
  // 那一步本身也是投递，必须随主结果一起上报，否则调用方只看到后半截。
  prefocus?: { tool: string; response: DeliveryResponse };
};

export type Observation = {
  // 动作关掉窗口后无法重新采集。这不是动作失败，用 unavailable 如实区分。
  state?: WindowState;
  hasBaseline: boolean;
  added: string[];
  removed: string[];
  changed: string[];
  unavailable?: string;
};

export type ExecutionResult = {
  delivery: Delivery;
  target?: TargetResolution;
  observation?: Observation;
  verification?: {
    target: string;
    verdict: "confirmed" | "timeout";
    elapsedMs: number;
    before?: string;
    after?: string;
    mediaState?: "playing" | "paused" | "unknown";
    mediaTitle?: string;
    // media: 等的是系统级 now-playing，不是目标窗口那个应用，必须把实际播放器一并报出来。
    mediaApp?: string;
  };
};

export type VerifyField = "exists" | "value" | "selected" | "enabled";

export type VerifyResult = {
  role: string;
  label: string;
  field: VerifyField;
  expected?: string;
  match?: { token: string; role: string };
  // 标签是否精确命中。子串命中也照常判定，但必须让调用方看见这次匹配有多松。
  exact: boolean;
  matchedLabel?: string;
  verdict: "satisfied" | "unsatisfied" | "unknown";
  reasons: string[];
  stable?: boolean;
  samples?: number;
  elapsedMs?: number;
  observed: unknown[];
};

export class ComputerUseError extends Error {
  constructor(message: string, readonly exitCode = 1) {
    super(message);
    this.name = "ComputerUseError";
  }
}

// ---------------------------------------------------------------------------
// 驱动适配器
// ---------------------------------------------------------------------------

export type DriverCall = { tool: string; args: Record<string, unknown>; imageOutFile?: string };

export interface DriverAdapter {
  call(tool: string, args: Record<string, unknown>, imageOutFile?: string): string;
}

export class CliDriverAdapter implements DriverAdapter {
  constructor(private readonly binary = process.env.CUA_DRIVER ?? "cua-driver") {}

  call(tool: string, args: Record<string, unknown>, imageOutFile?: string): string {
    const argv = ["call", tool, JSON.stringify(args)];
    if (imageOutFile) argv.push("--screenshot-out-file", imageOutFile);
    return execFileSync(this.binary, argv, { encoding: "utf8" });
  }
}

export class InMemoryDriverAdapter implements DriverAdapter {
  readonly calls: DriverCall[] = [];

  constructor(private readonly handler: (call: DriverCall) => string | Record<string, unknown>) {}

  call(tool: string, args: Record<string, unknown>, imageOutFile?: string): string {
    const invocation = { tool, args, imageOutFile };
    this.calls.push(invocation);
    const result = this.handler(invocation);
    return typeof result === "string" ? result : JSON.stringify(result);
  }
}

// ---------------------------------------------------------------------------
// 核心深模块：AutomationSession
// ---------------------------------------------------------------------------

type SessionOptions = {
  driver?: DriverAdapter;
  cacheDir?: string;
  mediaBin?: string;
  now?: () => number;
  sleep?: (ms: number) => void;
};

export class AutomationSession {
  readonly driver: DriverAdapter;
  readonly cacheDir: string;
  private readonly mediaBin: string;
  private readonly now: () => number;
  private readonly sleep: (ms: number) => void;

  private constructor(readonly pid: number, readonly windowId: number | undefined, options: SessionOptions) {
    if (!Number.isInteger(pid) || pid <= 0) throw new ComputerUseError("应用进程 PID 必须是正整数");
    if (windowId !== undefined && (!Number.isInteger(windowId) || windowId <= 0)) {
      throw new ComputerUseError("窗口 ID 必须是正整数");
    }
    this.driver = options.driver ?? new CliDriverAdapter();
    this.cacheDir = options.cacheDir ?? process.env.COMPUTER_USE_CACHE_DIR ?? join(tmpdir(), "computer-use");
    this.mediaBin = options.mediaBin ?? process.env.MEDIA_CONTROL_BIN ?? "media-control";
    this.now = options.now ?? Date.now;
    this.sleep = options.sleep ?? ((ms) => execFileSync("sleep", [String(ms / 1000)]));
  }

  static open(pid: number, windowId?: number, options: SessionOptions = {}): AutomationSession {
    return new AutomationSession(pid, windowId, options);
  }

  capture(options: { depth?: number; maxElements?: number; screenshotPath?: string; full?: boolean } = {}): WindowState {
    const wid = this.requireWindow();
    // 驱动按 lstat 逐段校验输出路径的祖先：/tmp 这类符号链接会被判成
    // 「existing ancestor is not a directory」而直接拒绝。先解软链再下发，
    // 回显的也是解开的路径，调用方照它去读文件一定读得到。
    let png = options.screenshotPath;
    if (png) {
      const dir = dirname(png);
      mkdirSync(dir, { recursive: true });
      png = join(realpathSync(dir), basename(png));
    }
    const part = png ? `${png}.part${process.pid}` : undefined;
    const args: Record<string, unknown> = { pid: this.pid, window_id: wid, include_screenshot: Boolean(png) };
    // 驱动默认深度 25、元素 2000；脚本自己砍到 3/300 会让整棵子树消失，而遍历成本由树本身决定，
    // 省下的时间接近零。只有调用方显式收紧时才下发上限。
    if (!options.full) {
      if (options.depth != null) args.max_depth = options.depth;
      if (options.maxElements != null) args.max_elements = options.maxElements;
    }
    if (part) args.screenshot_out_file = part;

    const raw = this.callDriver("get_window_state", args, `get_window_state failed for pid=${this.pid} window=${wid}`);
    const state = this.parseJson<WindowState>(raw, "get_window_state returned non-JSON");
    // 驱动以 stdout + exit 0 回报拒绝时 elements 必然缺席。那是它明确拒绝，
    // 不是树坏了，必须原样转述它给的 code 与 message。
    const refusal = state as unknown as { status?: string; refusal?: { code?: string; message?: string } };
    if (refusal.status === "refused" || refusal.refusal) {
      throw new ComputerUseError(`驱动拒绝 get_window_state：${refusal.refusal?.code ?? "refused"}${refusal.refusal?.message ? ` — ${refusal.refusal.message}` : ""}`);
    }
    if (!Array.isArray(state.elements)) throw new ComputerUseError(`get_window_state 返回无效 elements：${JSON.stringify(state)}`);

    if (part && png) {
      try {
        if (statSync(part).size === 0) throw new Error("驱动产出的图片为空");
        chmodSync(part, 0o600);
        renameSync(part, png);
      } catch (error) {
        rmSync(part, { force: true });
        throw new ComputerUseError(`未能取得有效图片 ${png}${this.errorSuffix(error)}`);
      }
      state.screenshot_file_path = png;
      state.screenshot_bounds = state.window_bounds ?? frameBounds(state.elements);
    } else {
      // 本次没截图。上一次的 PNG 凭证仍然有效：丢掉它会让 appshot → find → 像素点击
      // 这条正常链路必然报错。只沿用凭证，几何变化交给 requirePixel 判定。
      const prev = this.previousShot();
      if (prev) {
        state.screenshot_file_path = prev.screenshot_file_path;
        state.screenshot_width = prev.screenshot_width;
        state.screenshot_height = prev.screenshot_height;
        state.screenshot_bounds = prev.screenshot_bounds;
      }
    }

    if (state.tree_markdown && state.elements.length) {
      const meta = new Map<number, { desc?: string; actions?: string[] }>();
      for (const line of state.tree_markdown.split("\n")) {
        const m = line.match(/^\s*-\s*\[(\d+)\]\s+AX\w+(?:.*?\(([^)]+)\))?(?:.*?actions=\[([^\]]*)\])?/);
        if (m) meta.set(Number(m[1]), { desc: m[2]?.trim(), actions: m[3]?.split(",").map((s) => s.trim()) });
      }
      for (const el of state.elements) {
        if (el.element_index != null) {
          const item = meta.get(el.element_index);
          if (item?.desc) el.desc = item.desc;
          if (item?.actions) el.actions = item.actions;
        }
      }
    }

    mkdirSync(this.cacheDir, { recursive: true });
    writeFileSync(join(this.cacheDir, `${this.pid}-${wid}.json`), JSON.stringify({ savedAt: this.now(), state }), { mode: 0o600 });
    return state;
  }

  // capture 在窗口已消失时抛错。动作结论比观察重要，观察走这条容忍路径。
  private tryCapture(screenshotPath: string): { ok: true; state: WindowState } | { ok: false; reason: string } {
    try {
      return { ok: true, state: this.capture({ screenshotPath }) };
    } catch (e) {
      const m = e instanceof ComputerUseError ? e.message : String((e as { message?: string })?.message ?? e);
      return { ok: false, reason: m.replace(/\s+/g, " ").trim().slice(0, 200) };
    }
  }

  execute(action: AutomationAction, options: { observe?: boolean; waitTarget?: string; timeoutMs?: number } = {}): ExecutionResult {
    const wid = this.requireWindow();
    let beforeSig = "";
    let waitIdx: number | undefined;
    let waitId: { role: string; label: string } | undefined;
    let waitSub: string | undefined;
    if (options.waitTarget && !options.waitTarget.startsWith("media:")) {
      const m = /^(t\d+|s[0-9a-f]+:\d+)(?::(.*))?$/.exec(options.waitTarget);
      if (!m) throw new ComputerUseError(`无效的 --wait 目标 '${options.waitTarget}'`);
      waitIdx = tokenIndex(m[1]);
      waitSub = m[2];
      const el = this.loadSnapshot().elements.find((e) => e.element_index === waitIdx);
      if (el) {
        // 动作后必然重采快照，索引图随即被替换，所以等待期间按身份找回同一个元素。
        waitId = { role: el.role, label: el.label ?? el.desc ?? "" };
        beforeSig = waitSig(el, waitSub);
      }
    }

    // 执行动作
    const performed = this.perform(action, wid);

    // 动作后观察
    let observation: ExecutionResult["observation"];
    if (options.observe ?? true) {
      const before = this.readSnapshot();
      const shot = this.tryCapture(join(this.cacheDir, `${this.pid}-${wid}.png`));
      if (!shot.ok) {
        // 动作关掉目标窗口是正常结果，不是失败：观察降级为不可用，动作结论照常上报。
        observation = { hasBaseline: Boolean(before), added: [], removed: [], changed: [], unavailable: shot.reason };
      } else if (!before) {
        observation = { state: shot.state, hasBaseline: false, added: [], removed: [], changed: [] };
      } else {
        const after = shot.state;
        const f = (els: AxElement[]) => {
          const m = new Map<string, Set<string>>();
          for (const e of els) {
            const k = `${e.role.replace(/^AX/, "")} ${e.label ?? e.desc ?? ""}`.trim();
            const s = `${e.value ?? ""}${e.selected ? " [sel]" : ""}`.trim();
            const set = m.get(k) ?? new Set<string>();
            set.add(s);
            m.set(k, set);
          }
          return m;
        };
        const prev = f(before.elements);
        const curr = f(after.elements);
        const added: string[] = [];
        const removed: string[] = [];
        const changed: string[] = [];
        for (const [k, s] of curr) {
          const o = prev.get(k);
          if (!o) added.push(k);
          else if ([...o].sort().join(",") !== [...s].sort().join(",")) changed.push(`${k} "${[...o].sort().join(",")}"->"${[...s].sort().join(",")}"`);
        }
        for (const k of prev.keys()) if (!curr.has(k)) removed.push(k);
        observation = { state: after, hasBaseline: true, added, removed, changed };
      }
    }

    // 等待校验
    let verification: ExecutionResult["verification"];
    if (options.waitTarget) {
      const started = performance.now();
      const timeout = options.timeoutMs ?? 2000;
      if (options.waitTarget.startsWith("media:")) {
        const playing = options.waitTarget === "media:playing";
        let status: { ok: boolean; playing?: boolean; title?: string; app?: string } = { ok: false };
        let ok = false;
        while (performance.now() - started < timeout) {
          status = this.mediaStatus();
          if (status.ok && status.playing === playing) { ok = true; break; }
          this.sleep(150);
        }
        verification = { target: options.waitTarget, verdict: ok ? "confirmed" : "timeout", elapsedMs: Math.round(performance.now() - started), mediaState: status.ok ? (status.playing ? "playing" : "paused") : "unknown", mediaTitle: status.title, mediaApp: status.app };
      } else {
        const sig = (el?: AxElement) => el ? waitSig(el, waitSub) : "";
        let afterSig = beforeSig;
        let sample = observation?.state;
        let ok = false;
        while (true) {
          const el = sample ? waitElement(sample.elements, waitIdx, waitId) : undefined;
          if (el) {
            afterSig = sig(el);
            if (afterSig !== beforeSig) { ok = true; break; }
          }
          if (performance.now() - started >= timeout) break;
          this.sleep(150);
          try { sample = this.capture(); } catch { sample = undefined; }
        }
        verification = { target: options.waitTarget, verdict: ok ? "confirmed" : "timeout", elapsedMs: Math.round(performance.now() - started), before: beforeSig, after: afterSig };
      }
    }

    return { ...performed, observation, verification };
  }

  verify(req: { role: string; label: string; field: VerifyField; expected?: string; timeoutMs?: number }): VerifyResult {
    const wid = this.requireWindow();
    if (req.field !== "exists" && req.expected === undefined) throw new ComputerUseError(`field '${req.field}' 需要 expect 值`);
    if (["selected", "enabled"].includes(req.field) && !["true", "false"].includes(req.expected ?? "")) {
      throw new ComputerUseError(`field '${req.field}' 的 expect 只能是 true 或 false`);
    }
    // 驱动的 selector 只有 label_contains，精确性只能由脚本保证：子串命中更长的兄弟标签时
    // 驱动会照着那个更长的标签判定，实测把「不随机播放」当成「随机播放」返回了 satisfied。
    const norm = (s?: string | null) => (s ?? "").trim().toLowerCase();
    const roleOf = (s: string) => s.replace(/^AX/i, "").toLowerCase();
    const candidates = (this.readSnapshot()?.elements ?? []).filter((e) => roleOf(e.role) === roleOf(req.role));
    const exact = candidates.filter((e) => norm(e.label) === norm(req.label) || norm(e.desc) === norm(req.label));
    const contains = candidates.filter((e) => `${e.label ?? ""} ${e.desc ?? ""} ${e.value ?? ""}`.toLowerCase().includes(req.label.toLowerCase()));
    const used = exact.length ? exact : contains;
    if (used.length > 1) {
      throw new ComputerUseError(`选择器匹配 ${used.length} 个元素：${used.map((e) => `t${e.element_index} "${e.label ?? e.desc ?? ""}"`).join(", ")}；请用更精确的 label`);
    }
    const chosen = used[0];
    // 谓词指向脚本已经解析出的那个元素，而不是调用方给的子串，避免被更长的兄弟标签带偏。
    const sel = { role: req.role.replace(/^AX/i, ""), label_contains: (chosen?.label ?? "").trim() || (chosen?.desc ?? "").trim() || req.label };
    const predicate = req.field === "exists"
      ? { element: { selector: sel, exists: true } }
      : req.field === "value"
        ? { element: { selector: sel, value_equals: req.expected } }
        : req.field === "selected"
          ? { element: { selector: sel, selected: req.expected === "true" } }
          : { element: { selector: sel, enabled: req.expected === "true" } };

    const raw = this.callDriver("verify_state", { pid: this.pid, window_id: wid, expect: [predicate], timeout_ms: req.timeoutMs ?? 5000 }, `verify_state failed`);
    const out = this.parseJson<{ stable?: boolean; samples?: number; elapsed_ms?: number; predicates?: Array<{ status?: string; unknown_reason?: string; observed_json?: unknown }> }>(raw, "verify_state returned non-JSON");
    const statuses = out.predicates?.map((p) => p.status ?? "unknown") ?? [];
    const verdict = statuses.includes("unsatisfied") ? "unsatisfied" : statuses.length > 0 && statuses.every((s) => s === "satisfied") ? "satisfied" : "unknown";

    return {
      role: req.role,
      label: req.label,
      field: req.field,
      expected: req.expected,
      match: chosen ? { token: `t${chosen.element_index}`, role: chosen.role } : undefined,
      exact: exact.length === 1,
      matchedLabel: chosen ? (chosen.label ?? chosen.desc ?? "") : undefined,
      verdict,
      reasons: out.predicates?.map((p) => p.unknown_reason).filter(Boolean) as string[] ?? [],
      stable: out.stable,
      samples: out.samples,
      elapsedMs: out.elapsed_ms,
      observed: out.predicates?.map((p) => p.observed_json).filter((v) => v !== undefined) ?? [],
    };
  }

  zoom(x1: number, y1: number, x2: number, y2: number): { path: string; covered: Rect; scale: number; ratio: number } {
    const wid = this.requireWindow();
    // 四个数是两个点而不是两个点加宽高。传反了驱动只会拒绝、不产文件，
    // 随后的 chmod 会抛 ENOENT，看起来像权限问题，实际是参数非法。
    if (!(x2 > x1 && y2 > y1)) {
      throw new ComputerUseError("'zoom' 的四个数依次是左上与右下两点：需要 x2>x1 且 y2>y1（不要传宽高）");
    }
    const shot = this.requirePixel();
    // 边界是 PNG 像素（窗口左上角为原点），不是 ax= 报的屏幕点。落在这张图之外时驱动会
    // 把区域夹到边缘，交回一张与请求无关的图；这种输入必须拒绝而不是假装成功。
    const img = { width: shot.screenshotWidth, height: shot.screenshotHeight };
    if (img.width && img.height && (x2 <= 0 || y2 <= 0 || x1 >= img.width || y1 >= img.height)) {
      throw new ComputerUseError(`zoom 的四个边界必须在截图 PNG 内（本图 ${img.width}x${img.height}）；ax= 是屏幕点、不是 PNG 像素`);
    }
    // 调用方一律用 PNG 像素说话（与 click/drag 同一套），换算在驱动边界上做这一次。
    const ratio = this.rawPerPng(img);
    const rawX1 = Math.round(x1 * ratio), rawY1 = Math.round(y1 * ratio);
    const rawX2 = Math.round(x2 * ratio), rawY2 = Math.round(y2 * ratio);
    const target = join(this.cacheDir, `${this.pid}-${wid}-zoom.jpg`);
    const part = `${target}.part${process.pid}`;
    mkdirSync(this.cacheDir, { recursive: true });
    let raw = "";
    try {
      raw = this.driver.call("zoom", { pid: this.pid, window_id: wid, x1: rawX1, y1: rawY1, x2: rawX2, y2: rawY2 }, part);
    } catch (e) {
      rmSync(part, { force: true });
      throw new ComputerUseError(`zoom failed for pid=${this.pid} window=${wid}${this.errorSuffix(e)}`);
    }
    // 驱动以 stdout 回报拒绝时不会产文件，必须在这里拦住，否则错因会被 chmod 的 ENOENT 顶掉。
    if (!existsSync(part) || statSync(part).size === 0) {
      rmSync(part, { force: true });
      throw new ComputerUseError(`zoom 未产出图片${raw.trim() ? ` — ${raw.trim()}` : ""}`);
    }
    try {
      chmodSync(part, 0o600);
      renameSync(part, target);
    } catch (e) {
      rmSync(part, { force: true });
      throw new ComputerUseError(`未能取得有效图片 ${target}${this.errorSuffix(e)}`);
    }
    // 覆盖范围在原生空间里算（20% 边距与 500px 上限都长在驱动那一侧），再换算回 PNG 空间报给调用方：
    // 调用方读的是这张 PNG，量位置只能用 PNG 像素。
    const geom = zoomCovered(rawX1, rawY1, rawX2, rawY2, Math.round((img.width ?? 0) * ratio), Math.round((img.height ?? 0) * ratio));
    const covered: Rect = { x: geom.covered.x / ratio, y: geom.covered.y / ratio, width: geom.covered.width / ratio, height: geom.covered.height / ratio };
    const produced = zoomOutputSize(raw);
    return { path: target, covered, scale: produced ? produced.width / covered.width : geom.scale * ratio, ratio };
  }

  listWindows(): WindowRecord[] {
    return this.parseJson<{ windows?: WindowRecord[] }>(this.callDriver("list_windows", {}, "list_windows failed"), "").windows ?? [];
  }

  private perform(action: AutomationAction, wid: number): { delivery: ExecutionResult["delivery"]; target?: TargetResolution } {
    if (action.kind === "front") {
      return { delivery: { tool: "bring_to_front", response: this.parseJson(this.callDriver("bring_to_front", this.windowId === undefined ? { pid: this.pid } : { pid: this.pid, window_id: wid }, "bring_to_front failed"), "") } };
    }
    if (action.kind === "move") {
      let { width, height } = action;
      if (width === undefined || height === undefined) {
        const bounds = this.listWindows().find((w) => w.pid === this.pid && w.window_id === wid)?.bounds;
        width = width ?? bounds?.width ?? 1000;
        height = height ?? bounds?.height ?? 700;
      }
      return { delivery: { tool: "set_window_frame", response: this.parseJson(this.callDriver("set_window_frame", { pid: this.pid, window_id: wid, x: action.x, y: action.y, width, height }, "set_window_frame failed"), "") } };
    }
    if (action.kind === "drag") {
      const target = this.requirePixel();
      const args: Record<string, unknown> = { pid: this.pid, window_id: wid, from_x: action.fromX, from_y: action.fromY, to_x: action.toX, to_y: action.toY };
      if (action.foreground) args.delivery_mode = "foreground";
      return { delivery: { tool: "drag", response: this.parseJson(this.callDriver("drag", args, "drag failed"), "") }, target };
    }
    if (action.kind === "type") {
      const args: Record<string, unknown> = { pid: this.pid, window_id: wid, text: action.text };
      let target: TargetResolution | undefined;
      if (action.target) {
        const res = this.resolve(action.target.token);
        target = res.target;
        args.element_token = res.element.element_token;
        try {
          const raw = this.callDriver("set_value", { pid: this.pid, window_id: wid, element_token: res.element.element_token, value: action.text }, "");
          const resp = this.parseJson<ExecutionResult["delivery"]["response"]>(raw, "");
          if (resp.effect === "confirmed") return { delivery: { tool: "set_value", response: resp, setValueReadback: true }, target };
        } catch {}
      }
      if (action.foreground) args.delivery_mode = "foreground";
      return { delivery: { tool: "type_text", response: this.parseJson(this.callDriver("type_text", args, "type_text failed"), "") }, target };
    }
    if (action.kind === "key") {
      const mods = action.modifiers ?? [];
      const isHotkey = mods.length > 0;
      const args: Record<string, unknown> = { pid: this.pid, window_id: wid };
      if (isHotkey) args.keys = [...mods, action.key];
      else args.key = action.key;

      let target: TargetResolution | undefined;
      let prefocus: Delivery["prefocus"];
      if (action.target) {
        const res = this.resolve(action.target.token);
        target = res.target;
        if (isHotkey && (res.element.role === "AXTextField" || res.element.role === "AXTextArea")) {
          // hotkey 不认 element_token，必须先把焦点点上去，这一步本身就是一次投递。
          prefocus = this.clickCenter(res.element);
        } else {
          args.element_token = res.element.element_token;
        }
      }
      if (action.foreground) args.delivery_mode = "foreground";
      const tool = isHotkey ? "hotkey" : "press_key";
      return { delivery: { tool, response: this.parseJson(this.callDriver(tool, args, `${tool} failed`), ""), prefocus }, target };
    }
    if (action.kind === "scroll") {
      const res = this.resolve(action.target.token);
      const args: Record<string, unknown> = { pid: this.pid, window_id: wid, element_token: res.element.element_token, direction: action.direction, by: action.by };
      if (action.foreground) args.delivery_mode = "foreground";
      return { delivery: { tool: "scroll", response: this.parseJson(this.callDriver("scroll", args, "scroll failed"), "") }, target: res.target };
    }
    if (action.target.kind === "pixel") {
      let target: TargetResolution | undefined = action.target.fromZoom ? undefined : this.requirePixel();
      // 显式像素坐标是调用方自己的判断，照常投递；但落点若在屏幕可见区之外必须当场说明，
      // 否则这次投递在输出里看起来和「点了但没反应」完全一样。
      if (target?.kind === "pixel") {
        const off = this.offScreenNote(action.target.x, action.target.y);
        if (off) target = { ...target, note: off };
      }
      const args: Record<string, unknown> = { pid: this.pid, window_id: wid, x: action.target.x, y: action.target.y };
      if (action.target.fromZoom) args.from_zoom = true;
      if (action.kind === "double-click" || action.foreground) args.delivery_mode = "foreground";
      const tool = action.kind === "right-click" ? "right_click" : action.kind === "double-click" ? "double_click" : "click";
      return { delivery: { tool, response: this.parseJson(this.callDriver(tool, args, `${tool} failed`), "") }, target };
    }

    const res = this.resolve(action.target.token);
    const args: Record<string, unknown> = { pid: this.pid, window_id: wid, element_token: res.element.element_token };
    if (action.kind === "click") {
      if (!action.action && (res.element.role === "AXTextField" || res.element.role === "AXTextArea")) {
        return { delivery: this.clickCenter(res.element, action.foreground), target: res.target };
      }
      args.action = action.action ?? "press";
      if (action.foreground) args.delivery_mode = "foreground";
      return { delivery: { tool: "click", response: this.parseJson(this.callDriver("click", args, "click failed"), "") }, target: res.target };
    }
    if (action.kind === "double-click" || action.foreground) args.delivery_mode = "foreground";
    const tool = action.kind === "right-click" ? "right_click" : "double_click";
    return { delivery: { tool, response: this.parseJson(this.callDriver(tool, args, `${tool} failed`), "") }, target: res.target };
  }

  private clickCenter(element: AxElement, foreground = false) {
    if (element.element_index == null) throw new ComputerUseError("文本输入元素缺少 element_index");
    const state = this.capture({ screenshotPath: join(this.cacheDir, `${this.pid}-${this.requireWindow()}.png`) });
    const cur = state.elements.find((e) => e.element_index === element.element_index)?.frame;
    const root = state.elements.find((e) => e.role === "AXWindow")?.frame;
    const bounds = state.window_bounds ?? (root ? { x: root.x, y: root.y, width: root.w, height: root.h } : undefined);
    if (!cur || !bounds || !state.screenshot_width || !state.screenshot_height) {
      throw new ComputerUseError("文本输入元素无法换算为截图坐标，请重新运行 appshot 后使用像素坐标");
    }
    if (state.screenshot_frame_valid === false) {
      throw new ComputerUseError("驱动无法证明这张截图与窗口几何的对应关系（screenshot_frame_valid=false），无法把元素几何换算成像素落点；请重新运行 appshot");
    }
    const x = Math.round((cur.x - bounds.x + cur.w / 2) * (state.screenshot_width / bounds.width));
    const y = Math.round((cur.y - bounds.y + cur.h / 2) * (state.screenshot_height / bounds.height));
    // 文本控件没有可用的 AX 动作，只能靠像素点击聚焦。这条路由是脚本自己选的，就不能选一条
    // 注定被拒的路：窗口被推到屏幕外时这组像素要么被驱动拒绝、要么落到别的控件上。
    const off = this.offScreenReason(x, y, bounds, state.screenshot_width, state.screenshot_height);
    if (off) throw new ComputerUseError(`文本输入控件需要像素点击聚焦，但${off}`);
    const args: Record<string, unknown> = { pid: this.pid, window_id: this.requireWindow(), x, y };
    if (foreground) args.delivery_mode = "foreground";
    return { tool: "click", response: this.parseJson<ExecutionResult["delivery"]["response"]>(this.callDriver("click", args, "click failed"), "") };
  }

  private resolve(token: string): { element: AxElement; target: TargetResolution } {
    const idx = tokenIndex(token);
    if (idx === undefined) throw new ComputerUseError("元素应为 t<idx> 形式（如 t54），先用 'computer-use snapshot' 查询");
    const snap = this.loadSnapshot();
    const qualified = tokenSnapshotId(token);
    if (qualified && snap.snapshot_id && qualified !== snap.snapshot_id) {
      throw new ComputerUseError(`token ${token} 限定的快照 ${qualified} 不是当前快照 ${snap.snapshot_id}；请重新 appshot/find`);
    }
    // 驱动契约：索引图被下一次快照替换。脚本每次打印 token 都记下那次快照，
    // 于是「动作后复用旧 token」这种必然指错的情况可以在投递前拦住。
    const printed = recallPrinted();
    const known = printed && printed.pid === this.pid && printed.wid === this.requireWindow() ? printed : undefined;
    if (!qualified && known?.snapshotId && snap.snapshot_id && known.snapshotId !== snap.snapshot_id) {
      throw new ComputerUseError(`token ${token} 来自快照 ${known.snapshotId}，当前快照 ${snap.snapshot_id}；索引图已被下一次快照替换，请重新 appshot/find 取 token`);
    }
    const el = snap.elements.find((e) => e.element_index === idx);
    if (!el) throw new ComputerUseError(`index ${idx} 不在最近快照内，请重新运行 snapshot`);
    return {
      element: el,
      target: {
        kind: "element",
        snapshotId: snap.snapshot_id ?? el.element_token.split(":")[0],
        ageMs: this.now() - (this.readSnapshot()?.savedAt ?? this.now()),
        token,
        role: el.role,
        label: (el.label ?? el.desc ?? "").replace(/[\t\n]/g, " "),
        // 没有出处记录时无法判定是否漂移，如实标出来而不是默默放行。
        unqualified: !qualified && !known?.snapshotId ? true : undefined,
      },
    };
  }

  private requirePixel(): TargetResolution {
    const s = this.loadSnapshot();
    const path = s.screenshot_file_path;
    if (!path || !existsSync(path)) {
      throw new ComputerUseError(`像素坐标必须来自最近快照 PNG；请先运行 'computer-use appshot' 或 'snapshot ${this.pid} ${this.requireWindow()} --screenshot <path>'`);
    }
    // PNG 是拍下那一刻的几何。窗口被挪动后同一组像素指到别处，必须拒绝而不是照旧投递。
    const now = s.window_bounds ?? frameBounds(s.elements);
    if (s.screenshot_bounds && now && !sameRect(s.screenshot_bounds, now)) {
      throw new ComputerUseError(`窗口几何已变化（${fmtRect(s.screenshot_bounds)} → ${fmtRect(now)}），像素坐标已失效；请重新 appshot`);
    }
    // 驱动自己说这张截图与窗口几何的对应关系无法证明时，任何基于它的换算都是猜的。
    if (s.screenshot_frame_valid === false) {
      throw new ComputerUseError("驱动无法证明这张截图与窗口几何的对应关系（screenshot_frame_valid=false），像素坐标不可信；请重新运行 appshot");
    }
    return { kind: "pixel", snapshotId: s.snapshot_id ?? "unknown", ageMs: this.now() - (this.readSnapshot()?.savedAt ?? this.now()), screenshotWidth: s.screenshot_width, screenshotHeight: s.screenshot_height };
  }

  // zoom 是这套驱动里唯一按原生像素收坐标的工具：click/drag 收截图 PNG 像素，zoom 收
  // screenshot_scale 倍窗口点数的原生像素。比例随窗口宽度与截图压缩率变化，不同窗口不一样，
  // 因此必须每次实算，不能记常数（实测 kitty 2.2832、音乐 1.25、文本编辑 1.3139）。
  private rawPerPng(png: { width?: number; height?: number }): number {
    const s = this.loadSnapshot();
    const bounds = s.window_bounds ?? frameBounds(s.elements);
    const k = s.screenshot_scale;
    if (!bounds || !k || !png.width || bounds.width <= 0) {
      throw new ComputerUseError("无法确定驱动原生像素与截图像素的换算比（快照缺 screenshot_scale 或窗口几何）；请重新运行 appshot");
    }
    const ratio = (k * bounds.width) / png.width;
    if (!Number.isFinite(ratio) || ratio <= 0) {
      throw new ComputerUseError(`截图与窗口的几何不自洽（scale=${k} 窗口宽=${bounds.width} 截图宽=${png.width}），拒绝猜测换算比；请重新运行 appshot`);
    }
    return ratio;
  }

  // 显式像素坐标的落点检查：凭证可能来自上一次采集，几何已由 requirePixel 校验过。
  private offScreenNote(pngX: number, pngY: number): string | undefined {
    const s = this.loadSnapshot();
    const bounds = s.window_bounds ?? frameBounds(s.elements);
    const w = s.screenshot_width, h = s.screenshot_height;
    if (!bounds || !w || !h) return undefined;
    return this.offScreenReason(pngX, pngY, bounds, w, h);
  }

  // PNG 覆盖整个窗口，因此落点的屏幕坐标由同一个映射算出。落在窗口与屏幕的交集之外时
  // 返回一句可直接打印的说明，否则 undefined。
  private offScreenReason(pngX: number, pngY: number, bounds: Rect, shotW: number, shotH: number): string | undefined {
    const screen = screenSize();
    const point = { x: bounds.x + (pngX / shotW) * bounds.width, y: bounds.y + (pngY / shotH) * bounds.height };
    const visible = visibleRect(bounds, screen);
    if (insideRect(visible, point.x, point.y)) return undefined;
    return `像素点 (${pngX},${pngY}) 换算成屏幕坐标 (${Math.round(point.x)},${Math.round(point.y)}) 落在窗口与屏幕的交集之外（窗口 ${fmtRect(bounds)}，屏幕 ${fmtRect(screen)}，可见区 ${fmtRect(visible)}），驱动会以 "point lies outside window frame" 拒绝这次投递；先用 'computer-use move' 把窗口挪回屏幕内`;
  }

  // 上一次采集留下的像素凭证。读不出来就当没有，不把缓存损坏升级成采集失败。
  private previousShot(): Pick<WindowState, "screenshot_file_path" | "screenshot_width" | "screenshot_height" | "screenshot_bounds"> | undefined {
    try {
      const data = JSON.parse(readFileSync(join(this.cacheDir, `${this.pid}-${this.requireWindow()}.json`), "utf8"));
      const prev = data?.state as WindowState | undefined;
      return prev?.screenshot_file_path ? prev : undefined;
    } catch {
      return undefined;
    }
  }

  private readSnapshot(): { savedAt: number; elements: AxElement[]; snapshot_id?: string; screenshot_file_path?: string; screenshot_width?: number; screenshot_height?: number; window_bounds?: Rect; screenshot_bounds?: Rect } | undefined {
    const p = join(this.cacheDir, `${this.pid}-${this.requireWindow()}.json`);
    if (!existsSync(p)) return undefined;
    try {
      const data = JSON.parse(readFileSync(p, "utf8"));
      return { savedAt: data.savedAt, ...data.state };
    } catch {
      throw new ComputerUseError(`快照缓存内容无效 ${p}`);
    }
  }

  private loadSnapshot() {
    const s = this.readSnapshot();
    if (!s) throw new ComputerUseError(`找不到 ${this.pid}:${this.requireWindow()} 的快照缓存，请先运行 'computer-use snapshot ${this.pid} ${this.requireWindow()}'`);
    return s;
  }

  // media-control 的失败形态必须与「当前没有播放器」区分开：没有播放器时它 exit 0 且打印 null，
  // 那是合法的未知状态；二进制缺失或执行失败时这次等待根本无法判定，必须当场报错，
  // 否则输出与「动作没生效」的 timeout 一模一样（可复现：MEDIA_CONTROL_BIN=/nonexistent 与 /bin/false）。
  private mediaStatus(): { ok: boolean; playing?: boolean; title?: string; app?: string } {
    let out: string;
    try {
      out = execFileSync(this.mediaBin, ["get", "--now", "--no-artwork"], { encoding: "utf8", timeout: 1500 });
    } catch (e) {
      const code = e && typeof e === "object" && "code" in e ? e.code : undefined;
      if (code === "ENOENT") throw new ComputerUseError(`媒体状态工具未找到：${this.mediaBin}（用 MEDIA_CONTROL_BIN 指向 media-control）`);
      throw new ComputerUseError(`媒体状态工具执行失败：${this.mediaBin}${this.errorSuffix(e)}`);
    }
    const r = this.parseJson<{ playing?: boolean; title?: string; bundleIdentifier?: string } | null>(out, "媒体状态工具返回非 JSON");
    return r ? { ok: true, playing: Boolean(r.playing), title: r.title, app: r.bundleIdentifier } : { ok: false };
  }

  private callDriver(tool: string, args: Record<string, unknown>, ctx: string): string {
    try { return this.driver.call(tool, args); } catch (e) { throw new ComputerUseError(`${ctx}${this.errorSuffix(e)}`); }
  }

  private parseJson<T>(raw: string, ctx: string): T {
    try { return JSON.parse(raw) as T; } catch { throw new ComputerUseError(`${ctx}:\n${raw.trim()}`); }
  }

  private errorSuffix(e: unknown): string {
    const d = e as { stderr?: unknown; stdout?: unknown; message?: string };
    const m = String(d.stderr || d.stdout || d.message || "").trim();
    return m ? ` — ${m}` : "";
  }

  private requireWindow(): number {
    if (this.windowId === undefined) throw new ComputerUseError("该操作必须指定窗口 ID");
    return this.windowId;
  }
}

// ---------------------------------------------------------------------------
// CLI 交互与命令分发
// ---------------------------------------------------------------------------

const cacheDir = process.env.COMPUTER_USE_CACHE_DIR ?? join(tmpdir(), "computer-use");
const defaultDriver = new CliDriverAdapter();
// 脚本不下发上限时驱动按这个值截断；到达它说明可能还有元素没返回。
const DRIVER_DEFAULT_MAX_ELEMENTS = 2000;

const overview = `computer-use — macOS 窗口快照与自动化操作 CLI

目标寻址 (所有针对窗口的子命令通用):
  <pid>:<wid>      显式窗口，windows 的 TARGET 列可直接复制
  <应用名>          取该应用 z 序最前的窗口；同名多窗口写 <应用名>#标题片段
  省略              复用上一次的目标，open 也会顺带设定目标
  裸整数永远是动作参数而不是目标，因此 'click 500 235' 只能是像素坐标

闭环工作流 (SOP):
  1. 定位窗口   computer-use windows                     TARGET 列带 z 序、几何与视口外标记
                computer-use open <应用名>                冷启动并设定目标
  2. 读取界面   computer-use appshot [目标]               AX 树 + PNG 截图
                computer-use snapshot [目标]              只要 AX 树
                computer-use find [目标] <词>             只回匹配元素，大树省 token
  3. 执行动作   computer-use click / type / key / scroll / drag / zoom
                computer-use menu [目标] <菜单段...>       按菜单路径直接调用
  4. 确认结果   computer-use verify [目标] <role> <label> <field> [expect]

后台契约:
  · 默认走驱动的后台档：不抢焦点、不切工作区、不动光标
  · 元素目标 (t<idx>) 走 AX 档，后台窗口与屏外窗口都能用
  · 像素目标 (x y) 走 CGEvent 档，要求窗口在屏幕内可见
  · 只有 --foreground 会短暂置前再恢复原前台；其余路径不打扰使用者

子命令: apps open windows screen use menu appshot snapshot find
        click right-click double-click drag type key scroll zoom verify front move

单命令细节: computer-use --help <子命令>
目标寻址细节: computer-use --help target
输出字段语义: computer-use --help output`;

// 细节引导由脚本自带：每条的参数、标志、输出与坑位都写在这里，
// 技能文档只保留 SOP、跨命令坑位与常用举例。
const helpTopics: Record<string, string> = {
  apps: `computer-use apps [--recent [N]] [查询词]

列出应用及其运行状态与最近使用时间。
  --recent [N]   只按最近使用倒序取前 N 条，默认 15
  查询词         同时匹配应用名与 Bundle ID

输出列: 状态 / PID / 应用名称 / Bundle ID / 最近使用
  🟢 开启中 进程在跑，PID 可用
  ⚪️ 未开启 只是装过，用它拿不到窗口

来源是 Spotlight 索引加上 lsappinfo，因此正在运行但未被索引的应用也会出现。`,

  open: `computer-use open <应用名|bundle_id>

窗口已存在时只回报 pid 与 window_id，不重复启动；未启动则拉起并轮询等待窗口就绪。
目标含点号按 Bundle ID 处理，否则按应用名处理。

冷启动受系统首次启动耗时影响，轮询上限约 5 秒。超时后本条命令提示稍后自行运行
computer-use windows，而不是继续阻塞。`,

  windows: `computer-use windows [--all] [查询词]

按 z 序从前往后列出可操作窗口，TARGET 列可直接复制到任意子命令。
  --all       连零尺寸与隐藏窗口一起列出
  查询词       同时匹配应用名与标题

列: TARGET  Z  APP  TITLE  BOUNDS  STATE
  BOUNDS 是屏幕坐标与逻辑尺寸，不是 PNG 像素
  STATE 取值 ok / clipped / off-viewport / hidden / other-space，可叠加
    clipped        窗口被屏幕边缘裁掉一部分，剩下部分仍可投递像素事件
    off-viewport   窗口整个在屏幕外，像素投递必被拒绝
    hidden         未显示（最小化或未上屏），仅 --all 下出现
    other-space    在别的 Space 上，仅 --all 下出现

默认只列 is_on_screen 为真的窗口，也就是使用者眼前的东西。

off-viewport 表示窗口被平铺窗口管理器推到了屏幕外，Zed 与 Helium 常见。
这类窗口 AX 读写照常可用，像素投递会被驱动以 point lies outside window frame 拒绝，
先用 'computer-use move' 把它挪回屏幕内。

应用名会被系统本地化，例如 TextEdit 显示为「文本编辑」、Finder 显示为「访达」。`,

  target: `目标寻址

三种写法任选其一:
  <pid>:<wid>                     显式窗口，例如 1435:112
  <应用名> 或 <应用名>#标题片段     取该应用 z 序最前的窗口，例如 'Zed#cpa-plugins'
  省略                            复用上一次的目标

粘性目标在三种时机被记住: 显式指定窗口、open 成功、以及任何一次成功解析。
'computer-use use <目标>' 只设定目标并回显，不执行动作。

裸整数永远被当作动作参数而不是目标，因此 'click 500 235' 唯一含义是像素坐标，
不会与窗口参数混淆。应用名匹配是大小写不敏感的子串。

同一应用有多个窗口时取 z 序最前的那个，并在 note 行报告候选数量。

驱动契约：索引图 (t<idx>) 会被下一次快照替换。任何一次动作之后旧 token 都可能指向别的元素，
所以脚本在 token 与当前快照不一致时直接拒绝，要求重新 appshot/find 取 token。
token 也可写成驱动限定形式 s<snapshot>:<idx>；限定快照与当前快照不符时同样被拒。`,

  screen: `computer-use screen [--refresh]

打印主显示的逻辑尺寸与原点，用于判断窗口是否在视口外。

结果缓存 10 分钟；改过分辨率后用 --refresh 强制重读。`,

  use: `computer-use use <目标>

只设定粘性目标并回显，不执行任何动作。之后所有子命令都可以省略目标。

不带参数调用时回显当前粘性目标。`,

  menu: `computer-use menu [目标] <菜单段> [菜单段...]

按应用菜单路径直接调用菜单项，走驱动的无障碍接口，不依赖像素坐标。
例如: computer-use menu 文件 新建窗口

每段必须精确匹配，菜单项被禁用、缺失或匹配到多个时直接拒绝，不回退到像素点击。

注意: 逐层解析会真实展开该菜单。目标应用正被使用时不要用它探测菜单路径，
否则菜单栏会进入追踪状态并吞掉使用者接下来的点击与按键。`,

  appshot: `computer-use appshot [目标] [--full] [--screenshot <path>]

一次采集同时拿到 AX 树与 PNG 截图，并刷新动作 token。
  --full            完全解除遍历预算，交给驱动走到底
  --screenshot      截图另存到指定路径，默认写缓存目录 <pid>-<wid>.png

输出:
  snapshot= 快照 id   target= <pid>:<wid>   shown= 本次打印的元素数
  walked= 驱动本次走过的元素数
  tree= full | depth-limited(depth=N)   depth-limited 表示最深元素正好停在 N 层，可能还有更深的
  unindexed= 树里存在但没有 token 的节点数，只能读不能按 t<idx> 操作
  off-viewport 表示窗口在屏幕外：AX 可用，像素投递会被拒绝
  screenshot= 路径与 PNG 像素尺寸   coordinates=png-pixels
  t<idx> 行: 元素角色、标签、ax= 屏幕点、sel/on 标志
  ~ 行: 无索引节点，格式为 role / label / no-token

默认不下发遍历预算，交给驱动（深度 25、元素 2000）；--depth / --max-elements 可收紧。
只打印窗口视口内元素以控制 token 开销，元素多的时候先 find 投影，不要用 --all 全量打印。`,

  snapshot: `computer-use snapshot [目标] [--depth N] [--max-elements N] [--query Q] [--all] [--full] [--json]

只取 AX 树不截图，同样刷新动作 token。输出字段与 appshot 相同。
  --depth / --max-elements   收紧遍历预算；默认不下发，交给驱动（深度 25、元素 2000）
  --full                     完全解除遍历预算
  --query                    只打印命中项及其祖先链，缓存里仍是完整快照
  --all                      跳过视口过滤，输出全部已遍历元素
  --json                     输出原始 JSON，该模式不打印 duration_ms`,

  find: `computer-use find [目标] <匹配词>

只打印命中匹配词的元素及其祖先链，是 snapshot --query 的短入口。
在长列表或大树里先 find 定位，再按 t<idx> 操作，比全量打印省一个数量级的 token。

匹配为大小写不敏感的子串，同时比对角色、标签、值与描述。
末列 match/ancestor 标出命中与祖先；脚本取 token 只筛 match 行。
投影只作用于打印：快照缓存仍是完整树，所以后续动作的 observe 基线不受影响；
但驱动的遍历开销不变，大树依然要等。

驱动只给可操作元素发 token。命中落在无索引节点上时按 '~	角色	标签	no-token' 打印，
这类节点读得到、操作不了；需要动它们时改用像素坐标。`,

  click: `computer-use click [目标] <t<idx>|x y> [action] [--foreground] [--wait <t<idx>|media:playing>] [--timeout N]

  t<idx>         走元素语义动作
  x y            appshot PNG 像素坐标；窗口几何变化后这组坐标失效，脚本直接拒绝
  action         省略时按元素角色选择；文本控件自动改为中心像素点击，规避 AXPress -25206
  --foreground   只在后台投递失败且任务必须依赖前台输入时使用
  --wait         动作后轮询等属性位移，t<idx> 可加 :val 或 :sel 只比较该字段
                 t<idx> 动作后就失效，等待期间按角色加标签找回同一元素再比较
  --timeout      等待上限，默认 2000 毫秒

--wait media:* 等的是系统级 now-playing，不是目标窗口那个应用：实测对着文本编辑窗口等
media:playing，报回来的是浏览器里正在播的视频。输出行带 app=<bundle id> 与 title= 供核对。
media-control 缺失或执行失败时直接报错退出，不会退化成 timeout——那种情况下这次等待
根本无法判定。`,

  "right-click": `computer-use right-click [目标] <t<idx>|x y> [--foreground]

元素目标走上下文菜单，纯后台可用。像素目标走 PNG 坐标。`,

  "double-click": `computer-use double-click [目标] <t<idx>|x y>

默认短暂把目标窗口置前再恢复原前台。驱动的后台双击缺少 no-raise 激活前奏，
非前台 AppKit 窗口的双击会被静默忽略。`,

  drag: `computer-use drag [目标] <x1> <y1> <x2> <y2> [--foreground]

四个坐标都是最近一次 appshot 的 PNG 像素。用于框选、拖放、拖拽手柄。`,

  type: `computer-use type [目标] [t<idx>] <text> [--foreground] [--wait <t<idx>]

带 t<idx> 时优先走 Cocoa 原生 set_value 后台写入，回报 value_readback 验证；
驱动拒绝或元素不可写时回退到 type_text。不带 t<idx> 时投给当前焦点。`,

  key: `computer-use key [目标] [t<idx>] <key> [mods..] [--foreground] [--wait <t<idx>]

  computer-use key 1435:112 t1 return        后台聚焦该控件后按单键
  computer-use key 1435:112 space            投给当前焦点
  computer-use key 1435:112 t1 cmd a         带修饰键，改走驱动 hotkey 工具

带 t<idx> 时无需激活前台。纯单键走 press_key，带修饰键走 hotkey。
带修饰键且目标是文本控件时，脚本会先点击该控件聚焦，这次点击是独立投递，
会以 prefocus 行单独打印，不与随后的 hotkey 结果混在一起。`,

  scroll: `computer-use scroll [目标] <t<idx>> <up|down|left|right> [line|page] [--foreground]

按元素定位滚动，粒度默认 line。窗口被平铺窗口管理器推到屏外时驱动拒绝投递。`,

  zoom: `computer-use zoom [目标] <x1> <y1> <x2> <y2>

四个数是左上与右下两点（x2>x1、y2>y1），不是宽高；坐标是 appshot PNG 像素，
不是 t<idx> 行里 ax= 报的屏幕点，照抄 ax= 会落在图片之外，脚本直接拒绝。
截取区域放大成 JPEG，用于读小字或精确取点。

驱动里只有 zoom 收原生像素（未压缩截图），click/drag 收的是压缩后的 PNG 像素。
脚本在边界上补这次换算，ratio= 是当次的换算比（由驱动的 screenshot_scale、窗口点数
与截图宽度实算，随窗口变化，实测 1.25~2.28）；调用方只管给 PNG 像素，不要自己乘。

图片覆盖的范围不是你请求的那块：四周各外扩 20%，撞到图片边缘时夹取，
加完边距宽度超过 500 像素时整张等比缩小。输出行的 region= 与 scale= 为实际值：
    窗口 PNG 坐标 = region 左上角 + 图片内坐标 / scale
region= 与 scale= 都已换算回 PNG 空间，输出的坐标是 zoom 图内像素，
配合 computer-use click ... --from-zoom 使用。`,

  verify: `computer-use verify [目标] <role> <label子串> <exists|value|selected|enabled> [expect]

用 role 加 label 加 field 组成谓词请驱动判定，不依赖 AX 树差分。
退出码 0=satisfied  1=unsatisfied  2=unknown
unknown 表示驱动无法判定，例如 target_missing 或 unsupported_predicate，等于没有证据。

脚本先在当前快照里核对标签，精确匹配的元素优先；输出行回报 matched= 实际命中的标签与
exact= 是否精确。exact=false 表示只拿到子串命中，判定基于该标签而不是调用方给的词。
驱动侧的 selector 只有 label_contains，精确性由脚本保证。

value、selected、enabled 只对具备该属性的角色成立，AXWindow 一类会返回 unsupported_predicate。
选择器命中多个元素时本条命令直接拒绝，先用更精确的 label 收窄。
exists 没有否定形式，断言「不存在」驱动不接受。`,

  front: `computer-use front [目标]

把目标窗口提到最前并保持。会改变前台状态，使用前说明影响。`,

  move: `computer-use move [目标] <x> <y> [w] [h]

移动窗口，可选同时调整尺寸；省略 w 与 h 时沿用当前尺寸。会改变窗口状态，使用前说明影响。`,

  output: `动作结果字段

target:  本次动作解析到的目标及其快照 id 与年龄；年龄过大说明该重跑 appshot

投递行:  <工具>: effect=... route=... delivery=... evidence=...
  effect=confirmed        投递并已由驱动验证
  effect=unverifiable     只是投递出去了，不等于成功
  state=confirmed         驱动已验证
  state=delivered_unverified   投递完成但无验证

prefocus: 前置投递的结果。某些动作要分两步，例如对着文本控件按修饰键需先点击聚焦。
  该行与主投递各算一次事件，不要按一次事件理解。

observe: 动作后的新状态与有界差分，delta added/removed/changed 最多展开 6 行
  差分按角色加标签比对，滚动不会把整棵树报成变更
  差分为空只说明 AX 树没看到变化，要结论就上 verify 或 --wait
  observe: unavailable (原因) 表示动作之后窗口已无法采集，例如刚被关掉。
  这只是观察失败，动作结论照常按上面的 effect 判读。

hint:  effect 为 unverifiable 且 observe 差分为空时给出，行里会写明本次用的是哪个工具，
  表示这次投递没有留下任何 AX 回执。generic click 本就没有独立回执，
  effect=unverifiable 是常态而不是失败，不能据此断定控件不可用。

note:  两种来源：像素目标的落点在窗口与屏幕的交集之外（驱动会以
  point lies outside window frame 拒绝这次投递，先用 move 把窗口挪回屏幕内）；
  以及 token 未经快照限定、索引可能已漂移。

verify:  target  verdict=confirmed|timeout  diff / state  elapsed
  verdict=timeout 时退出码为 2

所有子命令在内容后空一行输出 duration_ms=<毫秒>，--json 模式除外。`,
};

function helpText(topic?: string): string {
  if (!topic) return overview;
  const detail = helpTopics[topic];
  if (detail) return detail;
  return `未知帮助主题 '${topic}'；可用主题: ${Object.keys(helpTopics).join(", ")}\n\n${overview}`;
}

function fail(msg: string): never { throw new ComputerUseError(msg); }

// ---------------------------------------------------------------------------
// 目标寻址：<pid>:<wid>、<应用名[#标题子串]>、或省略走粘性目标
// ---------------------------------------------------------------------------

// 目标写成单个参数，逗号前面带冒号更好认。裸整数永远是动作参数而不是目标，
// 这条规则让「click 500 235」只能是像素坐标，不需要靠参数个数猜。
const MIN_WINDOW_EDGE = 2;

function allWindows(): WindowRecord[] {
  try {
    const raw = defaultDriver.call("list_windows", {});
    return (JSON.parse(raw) as { windows?: WindowRecord[] }).windows ?? [];
  } catch (e) {
    throw new ComputerUseError(`list_windows failed${describeError(e)}`);
  }
}

// 一次抓取，两种视图。listed 是使用者眼前的窗口，适合直接列给人看；
// all 是几何上可操作的窗口，含隐藏与别的 Space，用于按应用名兜底找窗口。
function scanWindows(): { listed: WindowRecord[]; all: WindowRecord[] } {
  const all = allWindows().filter((w) => {
    const b = w.bounds;
    return !b || (b.width >= MIN_WINDOW_EDGE && b.height >= MIN_WINDOW_EDGE);
  });
  const listed = all.filter((w) => {
    const b = w.bounds;
    return Boolean(b) && b!.width >= MIN_WINDOW_EDGE && b!.height >= MIN_WINDOW_EDGE && w.is_on_screen === true;
  });
  return { listed, all };
}

// 视口状态按屏幕坐标与几何实算。is_on_screen 靠不住：
// 被平铺窗口管理器推到 x=1919 的窗口依然报 on_screen=true。
function viewportState(bounds: WindowRecord["bounds"], screen: { width: number; height: number }): "visible" | "clipped" | "outside" {
  if (!bounds) return "visible";
  const visW = Math.min(bounds.x + bounds.width, screen.width) - Math.max(bounds.x, 0);
  const visH = Math.min(bounds.y + bounds.height, screen.height) - Math.max(bounds.y, 0);
  if (visW <= 0 || visH <= 0) return "outside";
  if (visW < bounds.width || visH < bounds.height) return "clipped";
  return "visible";
}

// 窗口几何有三个来源（驱动的 window_bounds、AXWindow 的 frame、PNG 拍下时的几何），
// 形状一致。像素坐标的有效性就建立在这个相等判断上，所以比较按 Rect 统一做。
function frameBounds(elements: AxElement[]): Rect | undefined {
  const f = elements.find((e) => e.role === "AXWindow")?.frame;
  return f ? { x: f.x, y: f.y, width: f.w, height: f.h } : undefined;
}

function sameRect(a: Rect, b: Rect): boolean {
  return Math.round(a.x) === Math.round(b.x) && Math.round(a.y) === Math.round(b.y)
    && Math.round(a.width) === Math.round(b.width) && Math.round(a.height) === Math.round(b.height);
}

// 屏幕与窗口的交集。像素投递只有落在这个矩形内才会被驱动接受：窗口被平铺管理器推到屏幕外时
// 驱动回 'point lies outside window frame'，而调用方从输出里看不出投递根本没落地。
function visibleRect(bounds: Rect, screen: Rect): Rect {
  const left = Math.max(bounds.x, screen.x);
  const top = Math.max(bounds.y, screen.y);
  return {
    x: left,
    y: top,
    width: Math.max(0, Math.min(bounds.x + bounds.width, screen.x + screen.width) - left),
    height: Math.max(0, Math.min(bounds.y + bounds.height, screen.y + screen.height) - top),
  };
}

function insideRect(r: Rect, x: number, y: number): boolean {
  return x >= r.x && x <= r.x + r.width && y >= r.y && y <= r.y + r.height;
}

function fmtRect(r: Rect): string {
  return `${Math.round(r.x)},${Math.round(r.y)} ${Math.round(r.width)}x${Math.round(r.height)}`;
}

// 驱动的 zoom 不是「按请求裁剪」：它在请求区域外各留 20% 边距，碰到图片边缘时夹取，
// 加完边距宽度仍超过 500 像素时再整体等比缩小。输出图的原点因此不在请求的左上角，
// 调用方要按图片像素量位置就必须知道真实覆盖范围与缩放比。坐标一律按原生像素算（zoom 的入参空间）。
function zoomCovered(x1: number, y1: number, x2: number, y2: number, width?: number, height?: number): { covered: Rect; scale: number } {
  const left = Math.max(0, x1 - (x2 - x1) * 0.2);
  const top = Math.max(0, y1 - (y2 - y1) * 0.2);
  const right = Math.min(width ?? Infinity, x2 + (x2 - x1) * 0.2);
  const bottom = Math.min(height ?? Infinity, y2 + (y2 - y1) * 0.2);
  const w = right - left;
  return { covered: { x: left, y: top, width: w, height: bottom - top }, scale: w > 500 ? 500 / w : 1 };
}

// 驱动回报里的图片实际尺寸，用来把「图片像素」精确换回 PNG 像素；拿不到时退回按边距推算的倍率。
function zoomOutputSize(raw: string): { width: number; height: number } | undefined {
  try {
    const r = JSON.parse(raw) as { width?: unknown; height?: unknown };
    return typeof r.width === "number" && typeof r.height === "number" ? { width: r.width, height: r.height } : undefined;
  } catch {
    return undefined;
  }
}

function screenSize(force = false): { x: number; y: number; width: number; height: number } {
  const p = join(cacheDir, "screen.json");
  if (!force) try {
    const cached = JSON.parse(readFileSync(p, "utf8"));
    if (Date.now() - cached.at < 10 * 60_000) return cached.rect;
  } catch {}
  const r = (() => {
    try {
      return JSON.parse(defaultDriver.call("get_screen_size", {})) as { width: number; height: number };
    } catch (e) {
      throw new ComputerUseError(`get_screen_size failed${describeError(e)}`);
    }
  })();
  const rect = { x: 0, y: 0, width: r.width, height: r.height };
  try {
    mkdirSync(cacheDir, { recursive: true });
    writeFileSync(p, JSON.stringify({ at: Date.now(), rect }), { mode: 0o600 });
  } catch {}
  return rect;
}

function rememberTarget(pid: number, wid: number): void {
  try {
    mkdirSync(cacheDir, { recursive: true });
    writeFileSync(join(cacheDir, "target.json"), JSON.stringify({ pid, wid, at: Date.now() }), { mode: 0o600 });
  } catch {}
}

function recallTarget(): { pid: number; wid: number } | undefined {
  try {
    const d = JSON.parse(readFileSync(join(cacheDir, "target.json"), "utf8"));
    if (Number.isInteger(d.pid) && d.pid > 0 && Number.isInteger(d.wid) && d.wid > 0) return { pid: d.pid, wid: d.wid };
  } catch {}
  return undefined;
}

// 打印出去的那份索引图是哪个快照印的。驱动契约写的是「索引图被下一次快照替换」，
// 所以任何一次动作之后再拿旧 token 都必然指向别的元素，这件事必须能判出来。
function rememberPrinted(pid: number, wid: number, snapshotId?: string): void {
  try {
    mkdirSync(cacheDir, { recursive: true });
    writeFileSync(join(cacheDir, "printed.json"), JSON.stringify({ pid, wid, snapshotId, at: Date.now() }), { mode: 0o600 });
  } catch {}
}

function recallPrinted(): { pid: number; wid: number; snapshotId?: string } | undefined {
  try {
    const d = JSON.parse(readFileSync(join(cacheDir, "printed.json"), "utf8"));
    if (Number.isInteger(d.pid) && d.pid > 0 && Number.isInteger(d.wid) && d.wid > 0) {
      return { pid: d.pid, wid: d.wid, snapshotId: typeof d.snapshotId === "string" ? d.snapshotId : undefined };
    }
  } catch {}
  return undefined;
}

// 同名多窗口时只在「使用者看得见」的那些里排名，全在屏幕外的占位窗与 OmniWM 的
// 1920x30 横条 z 序反而更高，只看 z 会挑错。兜底时才考虑隐藏窗口。
function pickWindow(spec: string, pool: WindowRecord[], screen: { width: number; height: number }): { win?: WindowRecord; matched: number } {
  const hash = spec.indexOf("#");
  const app = (hash >= 0 ? spec.slice(0, hash) : spec).trim().toLowerCase();
  const title = hash >= 0 ? spec.slice(hash + 1).trim().toLowerCase() : undefined;
  const matched = pool.filter((w) => (w.app_name ?? "").toLowerCase().includes(app) && (title === undefined || (w.title ?? "").toLowerCase().includes(title)));
  const onView = (w: WindowRecord) => (viewportState(w.bounds, screen) === "outside" ? 0 : 1);
  const ranked = [...matched].sort((a, b) => onView(b) - onView(a) || (b.z_index ?? -1) - (a.z_index ?? -1));
  const seen = ranked.filter((w) => w.is_on_screen === true);
  return { win: (seen.length ? seen : ranked)[0], matched: matched.length };
}

type AppRecord = { name?: string; bundle_id?: string; pid?: number; running?: boolean; launch_path?: string };

// 应用名是本地化的：窗口列表里叫「音乐」，安装路径与 bundle id 里才叫 Music。
// 只有按名字找不到窗口时才走这一步，清单按天缓存，命中路径上不多付驱动往返。
function resolveApp(query: string): AppRecord | undefined {
  const path = join(cacheDir, "apps.json");
  let apps: AppRecord[] | undefined;
  try {
    const cached = JSON.parse(readFileSync(path, "utf8"));
    if (Date.now() - cached.at < 24 * 3600_000) apps = cached.apps;
  } catch {}
  if (!apps) {
    try {
      apps = (JSON.parse(defaultDriver.call("list_apps", {})) as { apps?: AppRecord[] }).apps ?? [];
      mkdirSync(cacheDir, { recursive: true });
      writeFileSync(path, JSON.stringify({ at: Date.now(), apps }), { mode: 0o600 });
    } catch {
      return undefined;
    }
  }
  const q = query.trim().toLowerCase();
  return apps.find((a) => {
    const file = (a.launch_path ?? "").split("/").pop()?.replace(/\.app$/i, "").toLowerCase() ?? "";
    return file === q || (a.bundle_id ?? "").toLowerCase().includes(q) || (a.name ?? "").toLowerCase().includes(q);
  });
}

type TakenTarget = { pid: number; wid: number; rest: string[]; note?: string };

// 元素 token：脚本自己印的 t<idx>，或驱动限定形式的 s<snapshot>:<idx>。
// 认出来是为了不把它当应用名去解析。
const TOKEN_RE = /^(?:t(\d+)|s[0-9a-f]+:(\d+))$/;

function tokenIndex(token: string): number | undefined {
  const m = TOKEN_RE.exec(token);
  return m ? Number(m[1] ?? m[2]) : undefined;
}

function tokenSnapshotId(token: string): string | undefined {
  const i = token.indexOf(":");
  return i > 0 ? token.slice(0, i) : undefined;
}

// --wait 的签名口径保持原样：:sel / :val 只看子字段，否则看值加选中加标签。
function waitSig(el: AxElement, sub?: string): string {
  return sub === "sel" ? String(Boolean(el.selected)) : sub === "val" ? String(el.value ?? "") : `${el.value ?? ""}|${Boolean(el.selected)}|${el.label ?? ""}`;
}

// 动作之后索引图被新快照替换，同一个 t<idx> 可能已经指向别的元素。
// 先按身份（角色加标签）找回唯一匹配，找不到唯一匹配才退回按索引查，例如 --wait t0 这类窗口元素。
function waitElement(elements: AxElement[], idx: number | undefined, id?: { role: string; label: string }): AxElement | undefined {
  if (idx == null) return undefined;
  if (id) {
    const same = elements.filter((e) => e.role === id.role && (e.label ?? e.desc ?? "") === id.label);
    if (same.length === 1) return same[0];
  }
  return elements.find((e) => e.element_index === idx);
}

// 位置参数有下限的命令（find 要匹配词、verify 要 role/label/field）必须留够动作参数：
// 不够就说明首个参数是动作参数而不是目标，例如 'verify Button 播放 selected true' 里的
// Button 是角色名，不是应用名。没有下限的命令保持原样，首个像目标的参数一律当目标。
function takeTarget(cmd: string, args: string[], opts: { minPositionals?: number } = {}): TakenTarget {
  const head = args[0];
  // 元素 token 与坐标都不是目标，只有带冒号的或非数字的名字才是。
  const looksLikeSpec = Boolean(head) && !head.startsWith("-") && !TOKEN_RE.test(head) && (head.includes(":") || !/^\d+(\.\d+)?$/.test(head));

  // 解析失败不再当场终止：调用方可能只是名字长得像目标。错误文案带回去由调用处决定是否上报。
  const resolveSpec = (spec: string): { pid: number; wid: number; note?: string } | { error: string } => {
    const colon = /^(\d+):(\d+)$/.exec(spec);
    if (colon) return { pid: Number(colon[1]), wid: Number(colon[2]) };
    if (spec.includes(":")) fail(`'${cmd}' 的目标 '${spec}' 格式无效，窗口目标应写成 <pid>:<wid>`);
    const scan = scanWindows();
    const screen = screenSize();
    let found = pickWindow(spec, scan.listed, screen);
    if (!found.win) found = pickWindow(spec, scan.all, screen);
    let localized: string | undefined;
    if (!found.win) {
      const app = resolveApp(spec);
      if (!app?.name) return { error: `找不到应用 '${spec}'\n\n先运行 'computer-use apps' 看装了什么，或运行 'computer-use windows' 直接看窗口` };
      found = pickWindow(app.name, scan.all, screen);
      if (!found.win) return { error: `'${app.name}' 已安装但没有可操作窗口\n\n先运行 'computer-use open ${spec}' 把它拉起来` };
      localized = `'${spec}' 在系统里叫「${app.name}」`;
    }
    const win = found.win;
    if (!win) return { error: `找不到应用 '${spec}' 的窗口\n\n先运行 'computer-use windows' 看已有窗口，或运行 'computer-use open ${spec}' 把它拉起来` };
    const note = localized ?? (found.matched > 1 ? `${found.matched} 个窗口匹配 '${spec}'，已取 ${win.pid}:${win.window_id}；要换窗口请写 '${spec}#标题片段'` : undefined);
    return { pid: win.pid, wid: win.window_id, note };
  };

  if (looksLikeSpec && (opts.minPositionals == null || args.length - 1 >= opts.minPositionals)) {
    const r = resolveSpec(head);
    if (!("error" in r)) {
      rememberTarget(r.pid, r.wid);
      return { ...r, rest: args.slice(1) };
    }
    if (opts.minPositionals == null) fail(r.error);
  }
  const sticky = recallTarget();
  if (sticky) return { ...sticky, rest: args };
  fail(`'${cmd}' 没有可用目标：既没给 <pid>:<wid> 或应用名，也没有上一次的目标\n\n先运行 'computer-use windows' 拿 <pid>:<wid>，或运行 'computer-use appshot <应用名>'`);
}

function describeError(e: unknown): string {
  const d = e as { stderr?: unknown; stdout?: unknown; message?: string };
  const m = String(d.stderr || d.stdout || d.message || "").trim();
  return m ? ` — ${m}` : "";
}

function strip(args: string[], ...flags: string[]): string[] {
  const skip = new Set(["--wait", "--timeout"]);
  const res: string[] = [];
  for (let i = 0; i < args.length; i++) {
    if (skip.has(args[i])) { i++; continue; }
    if (!flags.includes(args[i])) res.push(args[i]);
  }
  return res;
}

function waitOpts(args: string[]) {
  const wIdx = args.indexOf("--wait");
  const tIdx = args.indexOf("--timeout");
  return { waitTarget: wIdx >= 0 ? args[wIdx + 1] : undefined, timeoutMs: tIdx >= 0 ? Number(args[tIdx + 1]) || 2000 : 2000 };
}

function targetOf(args: string[], fromZoom = false): { kind: "element"; token: string } | { kind: "pixel"; x: number; y: number; fromZoom?: boolean } {
  if (TOKEN_RE.test(args[0] ?? "")) return { kind: "element", token: args[0] };
  const [x, y] = args.slice(0, 2).map(Number);
  // Number.isNaN 认不出 undefined：缺参数的空串会被当成像素 0,0 投出去。空 token 必须当场报错。
  if (!Number.isFinite(x) || !Number.isFinite(y)) fail("目标应为 t<idx> 或 PNG 像素坐标 x y");
  return { kind: "pixel", x, y, fromZoom };
}

// 投影在客户端做。驱动侧的 query 会把投影结果当作快照回填，下一次动作的 observe
// 基线就变成残缺树，原本存在的元素会被误报成新增。这里只影响打印，不动缓存。
// 命中项与祖先链在打印时长得一样，调用方无法区分，所以命中集合单独回传。
function projectToMatches(elements: AxElement[], pattern: string): { elements: AxElement[]; matches: Set<number> } {
  const q = pattern.toLowerCase();
  const byIndex = new Map<number, AxElement>();
  for (const e of elements) if (e.element_index != null) byIndex.set(e.element_index, e);
  const keep = new Set<number>();
  const matches = new Set<number>();
  for (const e of elements) {
    const text = `${e.role} ${e.label ?? ""} ${e.desc ?? ""} ${e.value ?? ""}`.toLowerCase();
    if (!text.includes(q)) continue;
    if (e.element_index == null) continue;
    keep.add(e.element_index);
    matches.add(e.element_index);
    for (let p = e.parent_index; p != null; p = byIndex.get(p)?.parent_index ?? null) {
      if (keep.has(p)) break;
      keep.add(p);
    }
  }
  return { elements: elements.filter((e) => e.element_index != null && keep.has(e.element_index)), matches };
}

// 元素行的唯一格式来源：snapshot、appshot 与 find 共用，避免三处各写一遍。
// find 投影出的祖先行与命中行外形一致，末列标出区别，取 token 只筛 match 行。
function elementRow(e: AxElement, mark?: "match" | "ancestor"): string {
  const f = e.frame;
  const flags = [e.selected && "sel", e.enabled && "on"].filter(Boolean).join(",");
  return `t${e.element_index}\t${e.role.replace(/^AX/, "")}\t${(e.label ?? e.value ?? "").replace(/[\t\n]/g, " ").trim()}\t${f ? `ax=(${Math.floor(f.x)},${Math.floor(f.y)})` : "ax=none"}\t${flags}${mark ? `\t${mark}` : ""}`;
}

// 驱动的 total_element_count 恒等于 returned_element_count、elements_complete 恒为 false，
// 两者都不携带信息。完整性只能自己算：深度墙看最深元素停在哪，缺失量看 markdown 与 elements 的节点数差。
function countMarkdownNodes(md?: string): number {
  if (!md) return 0;
  let n = 0;
  for (const line of md.split("\n")) if (/^\s*-/.test(line)) n++;
  return n;
}

function deepestDepth(elements: AxElement[]): number {
  let d = 0;
  for (const e of elements) if ((e.depth ?? 0) > d) d = e.depth;
  return d;
}

// 驱动只给可操作元素发 token，其余节点只出现在 markdown 里。它们真实存在于界面上，
// 但没有 token，所以只能读、不能按 <t<idx>> 操作——之前 find 对它们一律报零命中。
type TextOnlyNode = { role: string; label: string };

const MD_NODE = /^(\s*)-\s+(?:\[(\d+)\]\s+)?(AX\w+)(.*)$/;

function markdownOnlyNodes(md?: string): TextOnlyNode[] {
  if (!md) return [];
  const out: TextOnlyNode[] = [];
  for (const line of md.split("\n")) {
    const m = line.match(MD_NODE);
    if (!m || m[2] != null) continue; // 有索引的已在 elements 里，不重复列出
    const lbl = (m[4] ?? "").match(/^\s*(?:"([^"]*)"|\(([^)]*)\)|=\s*"([^"]*)")/);
    out.push({ role: m[3], label: lbl?.[1] ?? lbl?.[2] ?? lbl?.[3] ?? "" });
  }
  return out;
}

function describeDelivery(d: Delivery): string[] {
  const { tool, response: resp, setValueReadback } = d;
  if (setValueReadback) return [`${tool}: effect=confirmed (value_readback verified)`];
  const ev = resp.evidence?.flatMap((e) => e.kind ?? []).join(",") || "none";
  const chars = resp.delivered_chars == null || resp.requested_chars == null ? "" : ` chars=${resp.delivered_chars}/${resp.requested_chars}`;
  const state = resp.effect === "confirmed" ? "confirmed" : resp.effect === "unverifiable" ? "delivered_unverified" : resp.effect === "partial" ? "partial" : resp.refusal ? "refused" : "unknown";
  return [
    `${tool}: effect=${resp.effect ?? "unknown"} route=${resp.route ?? resp.path ?? "unknown"} delivery=${resp.delivery?.mode ?? "unknown"} evidence=${ev}${resp.code ? ` code=${resp.code}` : ""}${chars}${resp.retryable == null ? "" : ` retryable=${resp.retryable}`}${resp.retry_from_character == null ? "" : ` retry_from=${resp.retry_from_character}`}`,
    `state=${state}`,
  ];
}

function renderExec(r: ExecutionResult): void {
  if (r.target) {
    console.log(r.target.kind === "element"
      ? `target: snapshot=${r.target.snapshotId} age=${r.target.ageMs}ms ${r.target.token} ${r.target.role} ${r.target.label}`
      : `target: snapshot=${r.target.snapshotId} age=${r.target.ageMs}ms screenshot=${r.target.screenshotWidth ?? "?"}x${r.target.screenshotHeight ?? "?"}`);
    // 没有出处记录就无法判定这份索引图是否已被替换，如实标出而不是假装 token 一定有效。
    if (r.target.kind === "element" && r.target.unqualified) console.log("note=该 token 未经快照限定，索引可能已漂移");
    if (r.target.note) console.log(`note=${r.target.note}`);
  }
  // 前置聚焦是独立投递，先于主投递打印，避免调用方以为只有一次事件落到了应用上。
  if (r.delivery.prefocus) for (const l of describeDelivery(r.delivery.prefocus)) console.log(`prefocus ${l}`);
  for (const l of describeDelivery(r.delivery)) console.log(l);
  if (r.observation) {
    const { state, hasBaseline, added, removed, changed, unavailable } = r.observation;
    if (unavailable) {
      console.log(`observe: unavailable (${unavailable})`);
    } else {
      console.log(hasBaseline ? `observe: snapshot=${state?.snapshot_id ?? "?"} delta added=${added.length} removed=${removed.length} changed=${changed.length}` : `observe: snapshot=${state?.snapshot_id ?? "?"} baseline=none`);
      for (const l of [...added.map((v) => `  + ${v}`), ...removed.map((v) => `  - ${v}`), ...changed.map((v) => `  ~ ${v}`)].slice(0, 6)) console.log(l);
    }
  }
  // 投递出去不等于动作生效：generic click 在驱动侧没有独立回执（可复现：同一个传输按钮
  // 点下去 effect=unverifiable，树里却真的从「播放」变成「暂停」），所以这里只能如实说
  // 「没有任何回执」，不能替应用断定原因。
  const obs = r.observation;
  if (r.delivery.response.effect === "unverifiable" && obs && obs.hasBaseline && !obs.unavailable
    && obs.added.length === 0 && obs.removed.length === 0 && obs.changed.length === 0) {
    // 措辞必须跟着本次实际用的工具走：按键投递也走这条分支，说成 click 会把人引到错误的排查方向。
    console.log(`hint=动作已投递但 AX 树没有任何变化：本次 ${r.delivery.tool} 在驱动侧没有独立回执，effect=unverifiable 是常态而不是失败。也可能是这次投递没落到能响应的区域。用 appshot 截图目视核对，或改用 --foreground / 像素路径`);
  }
  if (r.verification) {
    const v = r.verification;
    const d = v.mediaState ? ` state=${v.mediaState}${v.mediaApp ? ` app=${v.mediaApp}` : ""}${v.mediaTitle ? ` title="${v.mediaTitle}"` : ""}` : ` diff="${v.before}"->"${v.after}"`;
    console.log(`verify: target=${v.target} verdict=${v.verdict}${d} elapsed=${v.elapsedMs}ms`);
    if (v.verdict === "timeout") process.exitCode = 2;
  }
}

function dispatch(cmd: string | undefined, args: string[]): void {
  if (!cmd || ["help", "-h", "--help"].includes(cmd)) {
    console.log(helpText(args[0]));
    return;
  }
  if (cmd === "apps") {
    const running = new Map<string, { pid: number; name: string; bid: string }>();
    try {
      for (const b of execFileSync("lsappinfo", ["list"], { encoding: "utf8" }).split(/\n(?=\d+\)\s*\")/)) {
        const name = b.match(/^\d+\)\s*\"([^\"]+)\"/)?.[1] ?? "";
        const bid = b.match(/bundleID=\"([^\"]+)\"/)?.[1] ?? "";
        const pid = Number(b.match(/pid\s*=\s*(\d+)/)?.[1]);
        if (pid && (name || bid)) {
          if (name) running.set(name.toLowerCase(), { pid, name, bid });
          if (bid) running.set(bid.toLowerCase(), { pid, name, bid });
        }
      }
    } catch {}
    const list: Array<{ name: string; bid: string; ms: number; running: boolean; pid: number }> = [];
    try {
      const paths = execFileSync("mdfind", ['kMDItemContentType == "com.apple.application-bundle" && kMDItemLastUsedDate >= $time.now(-30d)', "-onlyin", "/Applications", "-onlyin", "/System/Applications", "-onlyin", `${process.env.HOME}/Applications`], { encoding: "utf8" }).trim().split("\n").filter(Boolean);
      if (paths.length) {
        const mdls = execFileSync("mdls", ["-name", "kMDItemLastUsedDate", "-name", "kMDItemCFBundleIdentifier", ...paths], { encoding: "utf8", maxBuffer: 10 * 1024 * 1024 });
        const ids = [...mdls.matchAll(/kMDItemCFBundleIdentifier\s*=\s*(.*)/g)].map((m) => m[1].trim().replace(/^\"|\"$/g, ""));
        const dates = [...mdls.matchAll(/kMDItemLastUsedDate\s*=\s*(.*)/g)].map((m) => m[1].trim());
        paths.forEach((p, i) => {
          const name = p.split("/").pop()?.replace(/\.app$/, "") ?? "";
          const bid = ids[i] === "(null)" ? "" : ids[i] ?? "";
          const r = running.get(name.toLowerCase()) ?? running.get(bid.toLowerCase());
          list.push({ name, bid, ms: dates[i] === "(null)" ? 0 : new Date(dates[i] ?? "").getTime(), running: Boolean(r), pid: r?.pid ?? 0 });
        });
      }
    } catch {}
    const seen = new Set(list.map((a) => a.pid).filter(Boolean));
    for (const r of running.values()) if (!seen.has(r.pid)) { seen.add(r.pid); list.push({ name: r.name, bid: r.bid, ms: Date.now(), running: true, pid: r.pid }); }
    const q = (args[0] === "--recent" ? undefined : args[0])?.toLowerCase();
    const lim = Number(args[0] === "--recent" ? args[1] : args[1]) || 15;
    const rows = list.filter((a) => !q || a.name.toLowerCase().includes(q) || a.bid.toLowerCase().includes(q)).sort((a, b) => b.ms - a.ms).slice(0, lim);
    console.log("状态\tPID\t应用名称\tBundle ID\t最近使用");
    const ago = (ms: number) => { const s = Math.max(0, Math.floor((Date.now() - ms) / 1000)); return s < 60 ? `${s}秒前` : s < 3600 ? `${Math.floor(s / 60)}分钟前` : s < 86400 ? `${Math.floor(s / 3600)}小时前` : `${Math.floor(s / 86400)}天前`; };
    for (const a of rows) console.log(`${a.running ? "🟢 开启中" : "⚪️ 未开启"}\t${a.pid || "-"}\t${a.name}\t${a.bid || "-"}\t${a.ms ? ago(a.ms) : "较早之前"}`);
    return;
  }
  if (cmd === "open") {
    const target = args.find((a) => !a.startsWith("-"));
    if (!target) fail("'open' 命令必须指定应用名称或 Bundle ID；可先运行 'computer-use apps'");
    const scan = scanWindows();
    const screen = screenSize();
    const find = (n: string) => pickWindow(n, scan.listed, screen).win ?? pickWindow(n, scan.all, screen).win;
    let existing = find(target);
    // 应用名是本地化的，直接匹配失败才去查安装清单换算，命中路径上不付这次往返
    const app = existing ? undefined : resolveApp(target);
    if (!existing && app?.name) existing = find(app.name);
    if (existing) {
      rememberTarget(existing.pid, existing.window_id);
      console.log(`已在运行: ${existing.app_name} target=${existing.pid}:${existing.window_id} title="${existing.title ?? ""}"`);
      return;
    }
    let resp: { pid: number; name?: string; windows?: WindowRecord[] };
    try {
      resp = JSON.parse(defaultDriver.call("launch_app", app?.bundle_id ? { bundle_id: app.bundle_id } : target.includes(".") ? { bundle_id: target } : { name: target })) as { pid: number; name?: string; windows?: WindowRecord[] };
    } catch (e) {
      throw new ComputerUseError(`launch_app ${target} 失败${describeError(e)}`);
    }
    console.log(`已拉起应用: ${resp.name ?? target} pid=${resp.pid}`);
    let win = resp.windows?.find((w) => (w.bounds?.width ?? 0) >= MIN_WINDOW_EDGE);
    for (let i = 0; !win && i < 10; i++) {
      execFileSync("sleep", ["0.5"]);
      try { win = scanWindows().all.find((w) => w.pid === resp.pid); } catch {}
    }
    if (win) {
      rememberTarget(win.pid, win.window_id);
      console.log(`窗口就绪: target=${win.pid}:${win.window_id} title="${win.title ?? ""}"`);
    } else {
      console.log("窗口正在初始化中；稍后运行 computer-use windows");
    }
    return;
  }
  if (cmd === "windows" || cmd === "ls") {
    const all = args.includes("--all");
    const q = args.find((a) => !a.startsWith("-"))?.toLowerCase();
    const scan = scanWindows();
    const screen = screenSize();
    console.log(`screen=${screen.width}x${screen.height}  TARGET 列可直接复制到任意子命令`);
    console.log("TARGET\tZ\tAPP\tTITLE\tBOUNDS\tSTATE");
    const rows = (all ? scan.all : scan.listed)
      .filter((w) => !q || `${w.app_name ?? ""} ${w.title ?? ""}`.toLowerCase().includes(q))
      .sort((a, b) => (b.z_index ?? -1) - (a.z_index ?? -1));
    for (const w of rows) {
      const view = viewportState(w.bounds, screen);
      const b = w.bounds;
      const flags = [
        view === "outside" ? "off-viewport" : view === "clipped" ? "clipped" : "",
        all && w.is_on_screen === false ? "hidden" : "",
        all && w.on_current_space === false ? "other-space" : "",
      ].filter(Boolean).join(",");
      console.log([
        `${w.pid}:${w.window_id}`,
        w.z_index ?? "-",
        w.app_name ?? "",
        w.title ?? "",
        b ? `${Math.round(b.x)},${Math.round(b.y)} ${Math.round(b.width)}x${Math.round(b.height)}` : "none",
        flags || "ok",
      ].join("\t"));
    }
    return;
  }
  if (cmd === "screen") {
    const s = screenSize(args.includes("--refresh"));
    console.log(`screen=${s.width}x${s.height} origin=${s.x},${s.y}`);
    return;
  }
  if (cmd === "use") {
    const t = takeTarget("use", args);
    console.log(`target=${t.pid}:${t.wid}`);
    return;
  }
  if (cmd === "menu") {
    const t = takeTarget("menu", args);
    const path = t.rest.filter((a) => !a.startsWith("-"));
    if (!path.length) fail("'menu' 需要菜单路径，例如: computer-use menu 文件 新建");
    let raw: string;
    try {
      raw = defaultDriver.call("invoke_menu", { pid: t.pid, window_id: t.wid, path });
    } catch (e) {
      throw new ComputerUseError(`invoke_menu ${path.join(" > ")} 失败${describeError(e)}`);
    }
    console.log(`menu=${path.join(" > ")} ${raw.replace(/\s+/g, " ").trim()}`);
    return;
  }
  if (cmd === "front") {
    const t = takeTarget(cmd, args);
    renderExec(AutomationSession.open(t.pid, t.wid, { driver: defaultDriver, cacheDir }).execute({ kind: "front" }));
    return;
  }

  // find 要匹配词、verify 要 role/label/field：这两条命令的位置参数不够时，
  // 首个参数是动作参数而不是目标。
  const t = takeTarget(cmd, args, { minPositionals: cmd === "find" ? 1 : cmd === "verify" ? 3 : undefined });
  if (t.note) console.log(`note: ${t.note}`);
  const { pid, wid } = t;
  const s = AutomationSession.open(pid, wid, { driver: defaultDriver, cacheDir });
  const rest = t.rest;

  if (["click", "right-click", "double-click", "dblclick"].includes(cmd)) {
    const kind = cmd === "dblclick" ? "double-click" : cmd as "click" | "right-click" | "double-click";
    const fg = rest.includes("--foreground");
    const clean = strip(rest, "--foreground", "--from-zoom");
    if (!clean.length) fail(`'${kind}' 缺少${kind === "right-click" ? "右击" : kind === "double-click" ? "双击" : "点击"}目标\n\n先运行 'computer-use appshot ${pid}:${wid}' 拿元素 token，或直接给 PNG 像素坐标 x y`);
    const tgt = targetOf(clean, rest.includes("--from-zoom"));
    const act: AutomationAction = kind === "click"
      ? { kind, target: tgt, action: tgt.kind === "element" ? clean[1] : undefined, foreground: fg }
      : kind === "right-click"
        ? { kind, target: tgt, foreground: fg }
        : { kind, target: tgt };
    renderExec(s.execute(act, waitOpts(rest)));
    return;
  }
  if (cmd === "snapshot" || cmd === "appshot" || cmd === "find") {
    const sIdx = rest.indexOf("--screenshot");
    const shot = sIdx >= 0 ? rest[sIdx + 1] : undefined;
    if (rest.includes("--screenshot") && !shot) fail("--screenshot 需要保存路径");
    const dIdx = rest.indexOf("--depth");
    const mIdx = rest.indexOf("--max-elements");
    const qIdx = rest.indexOf("--query");
    const pattern = cmd === "find" ? rest.find((a) => !a.startsWith("-")) : qIdx >= 0 ? rest[qIdx + 1] : undefined;
    if (cmd === "find" && !pattern) fail("'find' 需要匹配词，例如: computer-use find 播放");
    const depth = dIdx >= 0 ? Number(rest[dIdx + 1]) || undefined : undefined;
    const useFull = rest.includes("--full");
    const state = s.capture({
      depth,
      maxElements: mIdx >= 0 ? Number(rest[mIdx + 1]) || undefined : undefined,
      screenshotPath: cmd === "appshot" ? shot ?? join(cacheDir, `${pid}-${wid}.png`) : shot,
      full: useFull,
    });
    if (rest.includes("--json")) return console.log(JSON.stringify(state));
    // 这次打印出去的 token 属于这一份索引图，记下来才能在下次动作前判出漂移。
    rememberPrinted(pid, wid, state.snapshot_id);
    const root = state.elements.find((e) => e.role === "AXWindow")?.frame;
    // find、--query 走投影；否则只留视口内元素。两条路径都不改写快照缓存。
    const projection = pattern ? projectToMatches(state.elements, pattern) : undefined;
    const vis = projection?.elements ?? (rest.includes("--all")
      ? state.elements
      : state.elements.filter((e) => {
        const f = e.frame;
        return f && !e.role.startsWith("AXMenu") && (!root || !(f.x + f.w <= root.x || f.x >= root.x + root.w || f.y + f.h <= root.y || f.y >= root.y + root.h));
      }));
    const screen = screenSize();
    const rect = state.window_bounds ?? (root ? { x: root.x, y: root.y, width: root.w, height: root.h } : undefined);
    const view = viewportState(rect, screen);
    // 命中词落在无索引节点上时投影结果为空，之前据此报「没有可操作元素」，
    // 把真实存在于界面上的文字说成不存在。这里把 markdown 里的命中项一并捞出来。
    const textOnly = pattern
      ? markdownOnlyNodes(state.tree_markdown).filter((n) => `${n.role} ${n.label}`.toLowerCase().includes(pattern.toLowerCase()))
      : [];
    const summarized = Boolean(pattern) && vis.length === 0 && textOnly.length > 0;
    const shown = vis.length + textOnly.length;
    // 驱动只给可操作元素发 token，markdown 与 elements 的节点数差就是「看得见但拿不到」的量。
    const unindexed = Math.max(0, countMarkdownNodes(state.tree_markdown) - state.elements.length);
    // 最深元素正好停在请求深度上，说明下面可能还被砍着；这是保守判定，不做额外一次探测。
    const tree = depth != null && deepestDepth(state.elements) >= depth ? `depth-limited(depth=${depth})` : "full";
    const flags = [view === "outside" ? "off-viewport" : view === "clipped" ? "clipped" : ""].filter(Boolean).join(" ");
    const head = cmd === "find" ? `find="${pattern}"` : `snapshot=${state.snapshot_id ?? "?"}`;
    console.log(`${head} target=${pid}:${wid} shown=${shown} walked=${state.elements.length} tree=${tree} unindexed=${unindexed}${flags ? ` ${flags}` : ""}`);
    if (state.screenshot_file_path) console.log(`screenshot=${state.screenshot_file_path} size=${state.screenshot_width ?? "?"}x${state.screenshot_height ?? "?"} coordinates=png-pixels`);
    const routes = state.background_input?.routes ?? [];
    const blocked = routes.filter((r) => r.status !== "available");
    // 空树或路由受阻时必须说清原因，否则调用方只能靠反复试错才发现动作落不下去。
    if (!vis.length || blocked.length) {
      const ax = state.background_input?.exact_window?.status;
      const detail = routes.map((r) => `${r.route}=${r.status}${r.reason ? `(${r.reason})` : ""}`).join(" ") || "unknown";
      console.log(`routes: ${ax ? `ax=${ax} ` : ""}${detail}`);
    }
    const notes: string[] = [];
    if (!state.elements.length) {
      notes.push("该窗口没有可操作元素；改用 'computer-use appshot' 拿截图走像素，或确认窗口是否还在初始化");
    } else if (!shown) {
      notes.push(pattern
        ? `匹配词没有命中；树里有 ${state.elements.length} 个元素，换词或用 '--all' 查看`
        : `视口内没有元素；树里有 ${state.elements.length} 个，用 '--all' 查看`);
    }
    if (summarized) notes.push(`命中的 ${textOnly.length} 个节点没有索引，只能读不能按 token 操作；需要操作时用像素坐标`);
    if (unindexed) notes.push(`树里有 ${unindexed} 个节点没有索引（驱动只给可操作元素发 token）；'find' 会把命中的这类节点标为 ~ 行`);
    if (!useFull && state.elements.length >= DRIVER_DEFAULT_MAX_ELEMENTS) notes.push(`已达驱动默认元素上限 ${DRIVER_DEFAULT_MAX_ELEMENTS}，可能仍有未返回元素；用 '--full' 解除`);
    if (view !== "visible" && rect) notes.push(`窗口大部分在屏幕外 (x=${Math.round(rect.x)} w=${Math.round(rect.width)} screen=${screen.width})；需要像素坐标时先用 'computer-use move' 挪回屏幕内`);
    for (const n of notes) console.log(`note=${n}`);
    for (const n of textOnly) console.log(`~\t${n.role.replace(/^AX/, "")}\t${n.label.replace(/[\t\n]/g, " ").trim()}\tno-token`);
    for (const e of vis.sort((a, b) => (a.frame?.y ?? Infinity) - (b.frame?.y ?? Infinity) || (a.frame?.x ?? Infinity) - (b.frame?.x ?? Infinity))) {
      console.log(elementRow(e, projection ? (projection.matches.has(e.element_index!) ? "match" : "ancestor") : undefined));
    }
    return;
  }
  if (cmd === "drag") {
    const clean = strip(rest, "--foreground");
    const [fx, fy, tx, ty] = clean.slice(0, 4).map(Number);
    if ([fx, fy, tx, ty].some(Number.isNaN) || clean.length < 4) fail("'drag' 拖拽必须指定 4 个像素坐标数值: <x1> <y1> <x2> <y2>");
    renderExec(s.execute({ kind: "drag", fromX: fx, fromY: fy, toX: tx, toY: ty, foreground: rest.includes("--foreground") }, waitOpts(rest)));
    return;
  }
  if (cmd === "zoom") {
    const [x1, y1, x2, y2] = rest.slice(0, 4).map(Number);
    if ([x1, y1, x2, y2].some(Number.isNaN) || rest.length < 4) fail("'zoom' 需要 4 个坐标数值");
    const z = s.zoom(x1, y1, x2, y2);
    // region= 是图片实际覆盖的范围（请求区域外加 20% 边距，撞边夹取、超宽缩小），
    // 不是请求的那块；换算回窗口 PNG 像素：png = region 左上角 + 图片像素 / scale。
    return console.log(`zoom=${z.path} region=${fmtRect(z.covered)} scale=${Number(z.scale.toFixed(3))} ratio=${Number(z.ratio.toFixed(4))} requested=(${x1},${y1})-(${x2},${y2}) coords=png`);
  }
  if (cmd === "type") {
    const clean = strip(rest, "--foreground");
    if (!clean.length) fail("'type' 缺少要输入的文本内容");
    const hasTgt = TOKEN_RE.test(clean[0]);
    renderExec(s.execute({ kind: "type", target: hasTgt ? { kind: "element", token: clean[0] } : undefined, text: clean.slice(hasTgt ? 1 : 0).join(" "), foreground: rest.includes("--foreground") }, waitOpts(rest)));
    return;
  }
  if (cmd === "key") {
    const clean = strip(rest, "--foreground");
    const hasTgt = TOKEN_RE.test(clean[0] ?? "");
    const key = clean[hasTgt ? 1 : 0];
    if (!key) fail("'key' 缺少按键名称");
    renderExec(s.execute({ kind: "key", target: hasTgt ? { kind: "element", token: clean[0] } : undefined, key, modifiers: clean.slice(hasTgt ? 2 : 1), foreground: rest.includes("--foreground") }, waitOpts(rest)));
    return;
  }
  if (cmd === "scroll") {
    const dir = rest[1] as "up" | "down" | "left" | "right";
    if (!TOKEN_RE.test(rest[0] ?? "") || !["up", "down", "left", "right"].includes(dir)) fail("'scroll' 需要 t<idx> 和 up/down/left/right");
    renderExec(s.execute({ kind: "scroll", target: { kind: "element", token: rest[0] }, direction: dir, by: rest.find((a) => ["line", "page"].includes(a)) ?? "line", foreground: rest.includes("--foreground") }, waitOpts(rest)));
    return;
  }
  if (cmd === "verify") {
    const clean = strip(rest);
    const [role, label, field, expected] = clean;
    if (!role || !label || !["exists", "value", "selected", "enabled"].includes(field)) fail("'verify' 缺少必要验证规则，格式: <role> <label> <field> [expect]");
    const tIdx = rest.indexOf("--timeout");
    const r = s.verify({ role, label, field: field as VerifyField, expected, timeoutMs: tIdx >= 0 ? Number(rest[tIdx + 1]) || 5000 : 5000 });
    console.log(`verify: role=${r.role} label~="${r.label}" matched="${r.matchedLabel ?? ""}" exact=${r.exact} field=${r.field}${r.expected == null ? "" : ` expected="${r.expected}"`}${r.match ? ` ${r.match.token} ${r.match.role}` : ""}`);
    if (!r.exact && r.matchedLabel) console.log(`note=label 未精确匹配，实际命中 "${r.matchedLabel}"；驱动谓词按该标签下发`);
    console.log(`verify: verdict=${r.verdict}${r.reasons.length ? ` reason=${r.reasons.join(",")}` : ""} stable=${r.stable ?? "?"} samples=${r.samples ?? "?"} elapsed=${r.elapsedMs ?? "?"}ms`);
    // 驱动 selector 只有 label_contains：脚本已按精确标签解析出元素，驱动仍可能因子串命中多个兄弟
    // 而无法判定。不说明的话，调用方会把这次 unknown 归因于自己给的标签不够精确。
    if (r.verdict === "unknown" && r.reasons.includes("multi_match")) {
      console.log("note=驱动侧 selector 只有 label_contains（子串），此次它匹配到多个元素因此无法判定；上面的 matched= 是脚本按精确标签解析出的元素，可用更精确的 label 或改用 appshot 目视核对");
    }
    if (r.observed.length) console.log(`observed=${r.observed.map((o) => JSON.stringify(o)).join(" ").slice(0, 300)}`);
    if (r.verdict === "unsatisfied") process.exitCode = 1;
    if (r.verdict === "unknown") process.exitCode = 2;
    return;
  }
  if (cmd === "move") {
    const [x, y] = rest.slice(0, 2).map(Number);
    if (Number.isNaN(x) || Number.isNaN(y)) fail("'move' 必须提供目标位置坐标: <x> <y> [w] [h]");
    renderExec(s.execute({ kind: "move", x, y, width: rest[2] ? Number(rest[2]) : undefined, height: rest[3] ? Number(rest[3]) : undefined }));
    return;
  }
  fail(`error: unknown subcommand '${cmd}'\n\n${overview}`);
}

if (import.meta.main) {
  const started = performance.now();
  try {
    const [cmd, ...args] = process.argv.slice(2);
    dispatch(cmd, args);
  } catch (e) {
    if (e instanceof ComputerUseError) {
      console.error(`error: ${e.message}`);
      process.exitCode = e.exitCode;
    } else {
      throw e;
    }
  } finally {
    if (!process.argv.includes("--json")) console.log(`\nduration_ms=${Math.round(performance.now() - started)}`);
  }
}
