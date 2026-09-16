#!/usr/bin/env bun
// computer-use — 窗口快照与自动化操作 CLI
// 核心架构：AutomationSession 统一内聚动作执行、后置观察、快照缓存刷新与等待校验。
import { execFileSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, readFileSync, renameSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

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

export type WindowState = {
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

export type WindowRecord = {
  pid: number;
  window_id: number;
  app_name?: string;
  title?: string;
  bounds?: { x: number; y: number; width: number; height: number };
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
  | { kind: "element"; snapshotId: string; ageMs: number; token: string; role: string; label: string }
  | { kind: "pixel"; snapshotId: string; ageMs: number; screenshotWidth?: number; screenshotHeight?: number };

export type ExecutionResult = {
  delivery: {
    tool: string;
    response: {
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
    setValueReadback?: boolean;
  };
  target?: TargetResolution;
  observation?: { state: WindowState; hasBaseline: boolean; added: string[]; removed: string[]; changed: string[] };
  verification?: {
    target: string;
    verdict: "confirmed" | "timeout";
    elapsedMs: number;
    before?: string;
    after?: string;
    mediaState?: "playing" | "paused" | "unknown";
    mediaTitle?: string;
  };
};

export type VerifyField = "exists" | "value" | "selected" | "enabled";

export type VerifyResult = {
  role: string;
  label: string;
  field: VerifyField;
  expected?: string;
  match?: { token: string; role: string };
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

  capture(options: { depth?: number; query?: string; maxElements?: number; screenshotPath?: string; full?: boolean } = {}): WindowState {
    const wid = this.requireWindow();
    const png = options.screenshotPath;
    const part = png ? `${png}.part${process.pid}` : undefined;
    const args: Record<string, unknown> = { pid: this.pid, window_id: wid, include_screenshot: Boolean(png) };
    if (!options.full) {
      args.max_depth = options.depth ?? 3;
      args.max_elements = options.maxElements ?? 300;
    }
    if (options.query) args.query = options.query;
    if (part && png) {
      mkdirSync(dirname(png), { recursive: true });
      args.screenshot_out_file = part;
    }

    const raw = this.callDriver("get_window_state", args, `get_window_state failed for pid=${this.pid} window=${wid}`);
    const state = this.parseJson<WindowState>(raw, "get_window_state returned non-JSON");
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

  execute(action: AutomationAction, options: { observe?: boolean; waitTarget?: string; timeoutMs?: number } = {}): ExecutionResult {
    const wid = this.requireWindow();
    let beforeSig = "";
    if (options.waitTarget && !options.waitTarget.startsWith("media:")) {
      const m = /^t(\d+)(?::(.*))?$/.exec(options.waitTarget);
      if (!m) throw new ComputerUseError(`无效的 --wait 目标 '${options.waitTarget}'`);
      const el = this.loadSnapshot().elements.find((e) => e.element_index === Number(m[1]));
      if (el) beforeSig = m[2] === "sel" ? String(Boolean(el.selected)) : m[2] === "val" ? String(el.value ?? "") : `${el.value ?? ""}|${Boolean(el.selected)}|${el.label ?? ""}`;
    }

    // 执行动作
    const performed = this.perform(action, wid);

    // 动作后观察
    let observation: ExecutionResult["observation"];
    if (options.observe ?? true) {
      const before = this.readSnapshot();
      const after = this.capture({ screenshotPath: join(this.cacheDir, `${this.pid}-${wid}.png`) });
      if (!before) {
        observation = { state: after, hasBaseline: false, added: [], removed: [], changed: [] };
      } else {
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
        let status: { ok: boolean; playing?: boolean; title?: string } = { ok: false };
        let ok = false;
        while (performance.now() - started < timeout) {
          status = this.mediaStatus();
          if (status.ok && status.playing === playing) { ok = true; break; }
          this.sleep(150);
        }
        verification = { target: options.waitTarget, verdict: ok ? "confirmed" : "timeout", elapsedMs: Math.round(performance.now() - started), mediaState: status.ok ? (status.playing ? "playing" : "paused") : "unknown", mediaTitle: status.title };
      } else {
        const m = /^t(\d+)(?::(.*))?$/.exec(options.waitTarget)!;
        const idx = Number(m[1]);
        const sub = m[2];
        const sig = (el?: AxElement) => el ? (sub === "sel" ? String(Boolean(el.selected)) : sub === "val" ? String(el.value ?? "") : `${el.value ?? ""}|${Boolean(el.selected)}|${el.label ?? ""}`) : "";
        let afterSig = beforeSig;
        let sample = observation?.state;
        let ok = false;
        while (true) {
          const el = sample?.elements.find((e) => e.element_index === idx);
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
    const sel = { role: req.role.replace(/^AX/i, ""), label_contains: req.label };
    const predicate = req.field === "exists"
      ? { element: { selector: sel, exists: true } }
      : req.field === "value"
        ? { element: { selector: sel, value_equals: req.expected } }
        : req.field === "selected"
          ? { element: { selector: sel, selected: req.expected === "true" } }
          : { element: { selector: sel, enabled: req.expected === "true" } };

    const matches = (this.readSnapshot()?.elements ?? []).filter((e) =>
      e.role.replace(/^AX/i, "").toLowerCase() === req.role.replace(/^AX/i, "").toLowerCase() &&
      `${e.label ?? ""} ${e.desc ?? ""} ${e.value ?? ""}`.toLowerCase().includes(req.label.toLowerCase())
    );
    if (matches.length > 1) {
      throw new ComputerUseError(`选择器匹配 ${matches.length} 个元素，请用更精确的 label`);
    }

    const raw = this.callDriver("verify_state", { pid: this.pid, window_id: wid, expect: [predicate], timeout_ms: req.timeoutMs ?? 5000 }, `verify_state failed`);
    const out = this.parseJson<{ stable?: boolean; samples?: number; elapsed_ms?: number; predicates?: Array<{ status?: string; unknown_reason?: string; observed_json?: unknown }> }>(raw, "verify_state returned non-JSON");
    const statuses = out.predicates?.map((p) => p.status ?? "unknown") ?? [];
    const verdict = statuses.includes("unsatisfied") ? "unsatisfied" : statuses.length > 0 && statuses.every((s) => s === "satisfied") ? "satisfied" : "unknown";

    return {
      role: req.role,
      label: req.label,
      field: req.field,
      expected: req.expected,
      match: matches.length === 1 ? { token: `t${matches[0].element_index}`, role: matches[0].role } : undefined,
      verdict,
      reasons: out.predicates?.map((p) => p.unknown_reason).filter(Boolean) as string[] ?? [],
      stable: out.stable,
      samples: out.samples,
      elapsedMs: out.elapsed_ms,
      observed: out.predicates?.map((p) => p.observed_json).filter((v) => v !== undefined) ?? [],
    };
  }

  zoom(x1: number, y1: number, x2: number, y2: number): string {
    const wid = this.requireWindow();
    this.requirePixel();
    const target = join(this.cacheDir, `${this.pid}-${wid}-zoom.jpg`);
    const part = `${target}.part${process.pid}`;
    mkdirSync(this.cacheDir, { recursive: true });
    try {
      this.driver.call("zoom", { pid: this.pid, window_id: wid, x1, y1, x2, y2 }, part);
    } catch (e) {
      rmSync(part, { force: true });
      throw new ComputerUseError(`zoom failed for pid=${this.pid} window=${wid}${this.errorSuffix(e)}`);
    }
    try {
      chmodSync(part, 0o600);
      renameSync(part, target);
    } catch (e) {
      rmSync(part, { force: true });
      throw new ComputerUseError(`未能取得有效图片 ${target}${this.errorSuffix(e)}`);
    }
    return target;
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
      if (action.target) {
        const res = this.resolve(action.target.token);
        target = res.target;
        if (isHotkey && (res.element.role === "AXTextField" || res.element.role === "AXTextArea")) {
          this.clickCenter(res.element);
        } else {
          args.element_token = res.element.element_token;
        }
      }
      if (action.foreground) args.delivery_mode = "foreground";
      const tool = isHotkey ? "hotkey" : "press_key";
      return { delivery: { tool, response: this.parseJson(this.callDriver(tool, args, `${tool} failed`), "") }, target };
    }
    if (action.kind === "scroll") {
      const res = this.resolve(action.target.token);
      const args: Record<string, unknown> = { pid: this.pid, window_id: wid, element_token: res.element.element_token, direction: action.direction, by: action.by };
      if (action.foreground) args.delivery_mode = "foreground";
      return { delivery: { tool: "scroll", response: this.parseJson(this.callDriver("scroll", args, "scroll failed"), "") }, target: res.target };
    }
    if (action.target.kind === "pixel") {
      const target = action.target.fromZoom ? undefined : this.requirePixel();
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
    const args: Record<string, unknown> = {
      pid: this.pid,
      window_id: this.requireWindow(),
      x: Math.round((cur.x - bounds.x + cur.w / 2) * (state.screenshot_width / bounds.width)),
      y: Math.round((cur.y - bounds.y + cur.h / 2) * (state.screenshot_height / bounds.height)),
    };
    if (foreground) args.delivery_mode = "foreground";
    return { tool: "click", response: this.parseJson<ExecutionResult["delivery"]["response"]>(this.callDriver("click", args, "click failed"), "") };
  }

  private resolve(token: string): { element: AxElement; target: TargetResolution } {
    const m = /^t(\d+)$/.exec(token);
    if (!m) throw new ComputerUseError("元素应为 t<idx> 形式（如 t54），先用 'computer-use snapshot' 查询");
    const idx = Number(m[1]);
    const snap = this.loadSnapshot();
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
      },
    };
  }

  private requirePixel(): TargetResolution {
    const s = this.loadSnapshot();
    if (!s.screenshot_file_path) throw new ComputerUseError(`像素坐标必须来自最近快照 PNG，请先运行 'computer-use snapshot ${this.pid} ${this.requireWindow()} --screenshot <path>'`);
    return { kind: "pixel", snapshotId: s.snapshot_id ?? "unknown", ageMs: this.now() - (this.readSnapshot()?.savedAt ?? this.now()), screenshotWidth: s.screenshot_width, screenshotHeight: s.screenshot_height };
  }

  private readSnapshot(): { savedAt: number; elements: AxElement[]; snapshot_id?: string; screenshot_file_path?: string; screenshot_width?: number; screenshot_height?: number } | undefined {
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

  private mediaStatus(): { ok: boolean; playing?: boolean; title?: string } {
    try {
      const r = JSON.parse(execFileSync(this.mediaBin, ["get", "--now", "--no-artwork"], { encoding: "utf8", timeout: 1500 }));
      return r ? { ok: true, playing: Boolean(r.playing), title: r.title } : { ok: false };
    } catch {
      return { ok: false };
    }
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

const overview = `computer-use — macOS 窗口快照与自动化操作 CLI

闭环工作流 (SOP):
  1. 定位窗口   computer-use windows                    列出 pid / window_id
                computer-use open <应用名|bundle_id>    冷启动并等待窗口就绪
  2. 读取界面   computer-use appshot <pid> <wid>         AX 树 + PNG 截图
                computer-use snapshot <pid> <wid>        只要 AX 树
  3. 执行动作   computer-use click / type / key / scroll / drag / zoom
  4. 确认结果   computer-use verify <pid> <wid> <role> <label> <field> [expect]

硬性契约:
  · 针对窗口的命令必须显式给出 <pid> <wid>，不接受隐式猜测
  · t<idx> 只在最近一次 appshot、snapshot 或动作之后有效，动作会刷新缓存
  · ax=(x,y) 是 AX 屏幕点，只用于定位；像素操作必须用 appshot 的 PNG 坐标
  · --wait 只在动作结果不是立即出现时使用

子命令: apps open windows appshot snapshot click right-click double-click
        drag type key scroll zoom verify front move

单命令细节: computer-use --help <子命令>
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

  windows: `computer-use windows

输出 PID / WINDOW_ID / APP / TITLE，制表符分隔。

应用名会被系统本地化，例如 TextEdit 显示为「文本编辑」、Finder 显示为「访达」。
按名称过滤窗口时按实际显示名匹配。`,

  appshot: `computer-use appshot <pid> <wid> [--full] [--screenshot <path>]

一次采集同时拿到 AX 树与 PNG 截图，并刷新动作 token。
  --full            交给驱动完整遍历预算，大树慎用
  --screenshot      截图另存到指定路径，默认写缓存目录 <pid>-<wid>.png

输出:
  snapshot= 快照 id   state=complete|truncated   viewport= 视口内元素数
  returned= / total=   screenshot= 路径与像素尺寸   coordinates=png-pixels
  t<idx> 行: 元素角色、标签、ax= 屏幕点、sel/on 标志

默认 depth=3、max-elements=300，只输出窗口视口内元素以控制 token 开销。
state=truncated 表示没遍历完；超出边界的元素会在 observe 差分里成批出现，那不是业务变化。`,

  snapshot: `computer-use snapshot <pid> <wid> [--depth N] [--max-elements N] [--query Q] [--all] [--json]

只取 AX 树不截图，同样刷新动作 token。
  --depth / --max-elements   覆盖默认遍历预算
  --query                    只过滤返回内容，不降低遍历成本
  --all                      跳过视口过滤，输出全部已遍历元素
  --json                     输出原始 JSON，该模式不打印 duration_ms`,

  click: `computer-use click <pid> <wid> <t<idx>|x y> [action] [--foreground] [--wait <t<idx>|media:playing>] [--timeout N]

  t<idx>         走元素语义动作
  x y            appshot PNG 像素坐标
  action         省略时按元素角色选择；文本控件自动改为中心像素点击，规避 AXPress -25206
  --foreground   只在后台投递失败且任务必须依赖前台输入时使用
  --wait         动作后轮询等属性位移，t<idx> 可加 :val 或 :sel 只比较该字段
  --timeout      等待上限，默认 2000 毫秒`,

  "right-click": `computer-use right-click <pid> <wid> <t<idx>|x y> [--foreground]

元素目标走上下文菜单，纯后台可用。像素目标走 PNG 坐标。`,

  "double-click": `computer-use double-click <pid> <wid> <t<idx>|x y>

默认短暂把目标窗口置前再恢复原前台。驱动的后台双击缺少 no-raise 激活前奏，
非前台 AppKit 窗口的双击会被静默忽略。`,

  drag: `computer-use drag <pid> <wid> <x1> <y1> <x2> <y2> [--foreground]

四个坐标都是最近一次 appshot 的 PNG 像素。用于框选、拖放、拖拽手柄。`,

  type: `computer-use type <pid> <wid> [t<idx>] <text> [--foreground] [--wait <t<idx>]

带 t<idx> 时优先走 Cocoa 原生 set_value 后台写入，回报 value_readback 验证；
驱动拒绝或元素不可写时回退到 type_text。不带 t<idx> 时投给当前焦点。`,

  key: `computer-use key <pid> <wid> [t<idx>] <key> [mods..] [--foreground] [--wait <t<idx>]

  computer-use key 1435 112 t1 return        后台聚焦该控件后按单键
  computer-use key 1435 112 space            投给当前焦点
  computer-use key 1435 112 t1 cmd a         带修饰键，改走驱动 hotkey 工具

带 t<idx> 时无需激活前台。纯单键走 press_key，带修饰键走 hotkey。`,

  scroll: `computer-use scroll <pid> <wid> <t<idx>> <up|down|left|right> [line|page] [--foreground]

按元素定位滚动，粒度默认 line。窗口被平铺窗口管理器推到屏外时驱动拒绝投递。`,

  zoom: `computer-use zoom <pid> <wid> <x1> <y1> <x2> <y2>

截取区域放大成 JPEG，宽度不超过 500 像素，四周各留 20% 边距。用于读小字或精确取点。
输出的坐标是 zoom 图内像素，配合 computer-use click ... --from-zoom 使用。`,

  verify: `computer-use verify <pid> <wid> <role> <label子串> <exists|value|selected|enabled> [expect]

用 role 加 label 加 field 组成谓词请驱动判定，不依赖 AX 树差分。
退出码 0=satisfied  1=unsatisfied  2=unknown
unknown 表示驱动无法判定，例如 target_missing 或 unsupported_predicate，等于没有证据。

value、selected、enabled 只对具备该属性的角色成立，AXWindow 一类会返回 unsupported_predicate。
选择器命中多个元素时本条命令直接拒绝，先用更精确的 label 收窄。
exists 没有否定形式，断言「不存在」驱动不接受。`,

  front: `computer-use front <pid> [wid]

把目标窗口提到最前。会改变窗口状态，使用前说明影响。`,

  move: `computer-use move <pid> <wid> <x> <y> [w] [h]

移动窗口，可选同时调整尺寸；省略 w 与 h 时沿用当前尺寸。会改变窗口状态，使用前说明影响。`,

  output: `动作结果字段

target:  本次动作解析到的目标及其快照 id 与年龄；年龄过大说明该重跑 appshot

投递行:  <工具>: effect=... route=... delivery=... evidence=...
  effect=confirmed        投递并已由驱动验证
  effect=unverifiable     只是投递出去了，不等于成功
  state=confirmed         驱动已验证
  state=delivered_unverified   投递完成但无验证

observe: 动作后的新状态与有界差分，delta added/removed/changed 最多展开 6 行
  差分按角色加标签比对，滚动不会把整棵树报成变更
  差分为空只说明 AX 树没看到变化，要结论就上 verify 或 --wait

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

function pair(cmd: string, args: string[]): [number, number] {
  const pid = Number(args[0]);
  const wid = Number(args[1]);
  if (!Number.isInteger(pid) || pid <= 0 || !Number.isInteger(wid) || wid <= 0) {
    fail(`'${cmd}' 必须显式指定目标窗口的整数 <pid> 和 <wid>作为前两个参数\n\n参数引导: 先运行 'computer-use windows' 查询窗口`);
  }
  return [pid, wid];
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
  if (/^t\d+$/.test(args[0] ?? "")) return { kind: "element", token: args[0] };
  const [x, y] = args.slice(0, 2).map(Number);
  if (Number.isNaN(x) || Number.isNaN(y)) fail("目标应为 t<idx> 或 PNG 像素坐标 x y");
  return { kind: "pixel", x, y, fromZoom };
}

function renderExec(r: ExecutionResult): void {
  if (r.target) {
    console.log(r.target.kind === "element"
      ? `target: snapshot=${r.target.snapshotId} age=${r.target.ageMs}ms ${r.target.token} ${r.target.role} ${r.target.label}`
      : `target: snapshot=${r.target.snapshotId} age=${r.target.ageMs}ms screenshot=${r.target.screenshotWidth ?? "?"}x${r.target.screenshotHeight ?? "?"}`);
  }
  const { tool, response: resp, setValueReadback } = r.delivery;
  if (setValueReadback) {
    console.log("set_value: effect=confirmed (value_readback verified)");
  } else {
    const ev = resp.evidence?.flatMap((e) => e.kind ?? []).join(",") || "none";
    const chars = resp.delivered_chars == null || resp.requested_chars == null ? "" : ` chars=${resp.delivered_chars}/${resp.requested_chars}`;
    console.log(`${tool}: effect=${resp.effect ?? "unknown"} route=${resp.route ?? resp.path ?? "unknown"} delivery=${resp.delivery?.mode ?? "unknown"} evidence=${ev}${resp.code ? ` code=${resp.code}` : ""}${chars}${resp.retryable == null ? "" : ` retryable=${resp.retryable}`}${resp.retry_from_character == null ? "" : ` retry_from=${resp.retry_from_character}`}`);
    const state = resp.effect === "confirmed" ? "confirmed" : resp.effect === "unverifiable" ? "delivered_unverified" : resp.effect === "partial" ? "partial" : resp.refusal ? "refused" : "unknown";
    console.log(`state=${state}`);
  }
  if (r.observation) {
    const { state, hasBaseline, added, removed, changed } = r.observation;
    console.log(hasBaseline ? `observe: snapshot=${state.snapshot_id ?? "?"} delta added=${added.length} removed=${removed.length} changed=${changed.length}` : `observe: snapshot=${state.snapshot_id ?? "?"} baseline=none`);
    for (const l of [...added.map((v) => `  + ${v}`), ...removed.map((v) => `  - ${v}`), ...changed.map((v) => `  ~ ${v}`)].slice(0, 6)) console.log(l);
  }
  if (r.verification) {
    const v = r.verification;
    const d = v.mediaState ? ` state=${v.mediaState}${v.mediaTitle ? ` title="${v.mediaTitle}"` : ""}` : ` diff="${v.before}"->"${v.after}"`;
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
    const target = args[0];
    if (!target || target.startsWith("-")) fail("'open' 命令必须指定应用名称或 Bundle ID；可先运行 'computer-use apps'");
    let raw: { windows?: WindowRecord[] };
    try {
      raw = JSON.parse(defaultDriver.call("get_accessibility_tree", {})) as { windows?: WindowRecord[] };
    } catch (e) {
      const err = e as { stderr?: unknown; stdout?: unknown; message?: string };
      const msg = String(err.stderr || err.stdout || err.message || "").trim();
      fail(`get_accessibility_tree failed${msg ? ` — ${msg}` : ""}`);
    }
    const exist = raw.windows?.find((w) => w.app_name?.toLowerCase().includes(target.toLowerCase()));
    if (exist) return console.log(`已在运行: ${exist.app_name} (pid=${exist.pid}, window_id=${exist.window_id})`);
    let resp: { pid: number; name?: string; windows?: WindowRecord[] };
    try {
      resp = JSON.parse(defaultDriver.call("launch_app", target.includes(".") ? { bundle_id: target } : { name: target })) as { pid: number; name?: string; windows?: WindowRecord[] };
    } catch (e) {
      const err = e as { stderr?: unknown; stdout?: unknown; message?: string };
      const msg = String(err.stderr || err.stdout || err.message || "").trim();
      fail(`launch_app failed${msg ? ` — ${msg}` : ""}`);
    }
    let win = resp.windows?.[0];
    for (let i = 0; !win && i < 10; i++) {
      execFileSync("sleep", ["0.5"]);
      try {
        win = (JSON.parse(defaultDriver.call("get_accessibility_tree", {})) as { windows?: WindowRecord[] }).windows?.find((w) => w.pid === resp.pid);
      } catch {}
    }
    console.log(`已拉起应用: ${resp.name ?? target} (pid=${resp.pid})`);
    console.log(win ? `窗口就绪: window_id=${win.window_id}, title="${win.title ?? ""}"` : "窗口正在初始化中；稍后运行 computer-use windows");
    return;
  }
  if (cmd === "windows") {
    console.log("PID\tWINDOW_ID\tAPP\tTITLE");
    let raw: { windows?: WindowRecord[] };
    try {
      raw = JSON.parse(defaultDriver.call("get_accessibility_tree", {})) as { windows?: WindowRecord[] };
    } catch (e) {
      const err = e as { stderr?: unknown; stdout?: unknown; message?: string };
      const msg = String(err.stderr || err.stdout || err.message || "").trim();
      fail(`get_accessibility_tree failed${msg ? ` — ${msg}` : ""}`);
    }
    for (const w of raw.windows ?? []) console.log([w.pid, w.window_id, w.app_name, w.title].join("\t"));
    return;
  }
  if (cmd === "front") {
    const pid = Number(args[0]);
    if (!Number.isInteger(pid) || pid <= 0) fail("'front' 必须指定应用进程 PID");
    renderExec(AutomationSession.open(pid, args[1] ? Number(args[1]) : undefined, { driver: defaultDriver, cacheDir }).execute({ kind: "front" }, { observe: Boolean(args[1]) }));
    return;
  }

  const [pid, wid] = pair(cmd, args);
  const s = AutomationSession.open(pid, wid, { driver: defaultDriver, cacheDir });
  const rest = args.slice(2);

  if (["click", "right-click", "double-click", "dblclick"].includes(cmd)) {
    const kind = cmd === "dblclick" ? "double-click" : cmd as "click" | "right-click" | "double-click";
    const fg = rest.includes("--foreground");
    const clean = strip(rest, "--foreground", "--from-zoom");
    if (!clean.length) fail(`'${kind}' 缺少${kind === "right-click" ? "右击" : kind === "double-click" ? "双击" : "点击"}目标；先运行 'computer-use appshot ${pid} ${wid}'`);
    const tgt = targetOf(clean, rest.includes("--from-zoom"));
    const act: AutomationAction = kind === "click"
      ? { kind, target: tgt, action: tgt.kind === "element" ? clean[1] : undefined, foreground: fg }
      : kind === "right-click"
        ? { kind, target: tgt, foreground: fg }
        : { kind, target: tgt };
    renderExec(s.execute(act, waitOpts(rest)));
    return;
  }
  if (cmd === "snapshot" || cmd === "appshot") {
    const sIdx = rest.indexOf("--screenshot");
    const shot = sIdx >= 0 ? rest[sIdx + 1] : undefined;
    if (rest.includes("--screenshot") && !shot) fail("--screenshot 需要保存路径");
    const dIdx = rest.indexOf("--depth");
    const mIdx = rest.indexOf("--max-elements");
    const qIdx = rest.indexOf("--query");
    const state = s.capture({
      depth: dIdx >= 0 ? Number(rest[dIdx + 1]) || undefined : undefined,
      maxElements: mIdx >= 0 ? Number(rest[mIdx + 1]) || undefined : undefined,
      query: qIdx >= 0 ? rest[qIdx + 1] : undefined,
      screenshotPath: cmd === "appshot" ? shot ?? join(cacheDir, `${pid}-${wid}.png`) : shot,
      full: cmd === "appshot" && rest.includes("--full"),
    });
    if (rest.includes("--json")) return console.log(JSON.stringify(state));
    if (cmd === "appshot") console.log(`appshot pid=${pid} window=${wid}`);
    const root = state.elements.find((e) => e.role === "AXWindow")?.frame;
    const vis = rest.includes("--all") || qIdx >= 0 ? state.elements : state.elements.filter((e) => {
      const f = e.frame;
      return f && !e.role.startsWith("AXMenu") && (!root || !(f.x + f.w <= root.x || f.x >= root.x + root.w || f.y + f.h <= root.y || f.y >= root.y + root.h));
    });
    console.log(`snapshot=${state.snapshot_id ?? "?"} state=${state.elements_complete === false ? "truncated" : "complete"} viewport=${vis.length} returned=${state.returned_element_count ?? state.elements.length} total=${state.total_element_count ?? state.elements.length} target=${state.pid}:${state.window_id}`);
    if (state._note) console.log(`note=${state._note.replace(/\s+/g, " ").trim()}`);
    if (state.screenshot_file_path) console.log(`screenshot=${state.screenshot_file_path} size=${state.screenshot_width ?? "?"}x${state.screenshot_height ?? "?"} coordinates=png-pixels`);
    for (const e of vis.sort((a, b) => (a.frame?.y ?? Infinity) - (b.frame?.y ?? Infinity) || (a.frame?.x ?? Infinity) - (b.frame?.x ?? Infinity))) {
      const f = e.frame;
      const flags = [e.selected && "sel", e.enabled && "on"].filter(Boolean).join(",");
      console.log(`t${e.element_index}\t${e.role.replace(/^AX/, "")}\t${(e.label ?? e.value ?? "").replace(/[\t\n]/g, " ").trim()}\t${f ? `ax=(${Math.floor(f.x)},${Math.floor(f.y)})` : "ax=none"}\t${flags}`);
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
    return console.log(`zoom=${s.zoom(x1, y1, x2, y2)} region=(${x1},${y1})-(${x2},${y2}) coords=zoom-pixels padding=20%`);
  }
  if (cmd === "type") {
    const clean = strip(rest, "--foreground");
    if (!clean.length) fail("'type' 缺少要输入的文本内容");
    const hasTgt = /^t\d+$/.test(clean[0]);
    renderExec(s.execute({ kind: "type", target: hasTgt ? { kind: "element", token: clean[0] } : undefined, text: clean.slice(hasTgt ? 1 : 0).join(" "), foreground: rest.includes("--foreground") }, waitOpts(rest)));
    return;
  }
  if (cmd === "key") {
    const clean = strip(rest, "--foreground");
    const hasTgt = /^t\d+$/.test(clean[0] ?? "");
    const key = clean[hasTgt ? 1 : 0];
    if (!key) fail("'key' 缺少按键名称");
    renderExec(s.execute({ kind: "key", target: hasTgt ? { kind: "element", token: clean[0] } : undefined, key, modifiers: clean.slice(hasTgt ? 2 : 1), foreground: rest.includes("--foreground") }, waitOpts(rest)));
    return;
  }
  if (cmd === "scroll") {
    const dir = rest[1] as "up" | "down" | "left" | "right";
    if (!/^t\d+$/.test(rest[0] ?? "") || !["up", "down", "left", "right"].includes(dir)) fail("'scroll' 需要 t<idx> 和 up/down/left/right");
    renderExec(s.execute({ kind: "scroll", target: { kind: "element", token: rest[0] }, direction: dir, by: rest.find((a) => ["line", "page"].includes(a)) ?? "line", foreground: rest.includes("--foreground") }, waitOpts(rest)));
    return;
  }
  if (cmd === "verify") {
    const clean = strip(rest);
    const [role, label, field, expected] = clean;
    if (!role || !label || !["exists", "value", "selected", "enabled"].includes(field)) fail("'verify' 缺少必要验证规则，格式: <role> <label> <field> [expect]");
    const tIdx = rest.indexOf("--timeout");
    const r = s.verify({ role, label, field: field as VerifyField, expected, timeoutMs: tIdx >= 0 ? Number(rest[tIdx + 1]) || 5000 : 5000 });
    console.log(`verify: role=${r.role} label~="${r.label}" field=${r.field}${r.expected == null ? "" : ` expected="${r.expected}"`}${r.match ? ` ${r.match.token} ${r.match.role}` : ""}`);
    console.log(`verify: verdict=${r.verdict}${r.reasons.length ? ` reason=${r.reasons.join(",")}` : ""} stable=${r.stable ?? "?"} samples=${r.samples ?? "?"} elapsed=${r.elapsedMs ?? "?"}ms`);
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
