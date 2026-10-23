import { afterEach, describe, expect, test } from "bun:test";
import { chmodSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const cli = join(import.meta.dir, "computer-use.ts");
const dirs: string[] = [];

afterEach(() => {
  for (const dir of dirs.splice(0)) rmSync(dir, { recursive: true, force: true });
});

function setup() {
  const dir = mkdtempSync(join(tmpdir(), "computer-use-test-"));
  dirs.push(dir);
  const log = join(dir, "calls.jsonl");
  const driver = join(dir, "driver.ts");
  writeFileSync(
    driver,
    `#!/usr/bin/env bun
import { appendFileSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
const [, , command, tool, rawArgs, ...flags] = process.argv;
const args = JSON.parse(rawArgs);
appendFileSync(${JSON.stringify(log)}, JSON.stringify({ tool, args }) + "\\n");
const calls = readFileSync(${JSON.stringify(log)}, "utf8").trim().split("\\n").length;
if (command !== "call") process.exit(2);
const flagPath = (name) => {
  const i = flags.indexOf(name);
  return i === -1 ? undefined : flags[i + 1];
};
const writeImage = (path) => {
  if (!path || process.env.MOCK_SKIP_IMAGE === "1") return;
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, Buffer.from([0x89, 0x50, 0x4e, 0x47]));
};
if (tool === "get_window_state") {
  if (process.env.MOCK_WINDOW_GONE && calls > Number(process.env.MOCK_WINDOW_GONE)) {
    console.error(JSON.stringify({ refusal: { code: "window_id_not_found", message: "window_id no longer exists" } }));
    process.exit(1);
  }
  if (process.env.MOCK_REFUSAL_STDOUT === "1") {
    console.log(JSON.stringify({ refusal: { code: "protected_resource_scope_invalid", message: "the output path's existing ancestor is not a directory" }, status: "refused" }));
    process.exit(0);
  }
  const pngPath = args.screenshot_out_file ?? flagPath("--screenshot-out-file");
  writeImage(pngPath);
  // 快照序号与状态翻转只跟随采集次数，不受 get_screen_size 之类无关调用影响
  const snaps = readFileSync(${JSON.stringify(log)}, "utf8").trim().split("\\n").filter((line) => line.includes("get_window_state")).length;
  const sid = "s" + snaps.toString(16).padStart(8, "0");
  const flipAfter = Number(process.env.MOCK_FLIP_AFTER ?? "1");
  const interactiveRole = process.env.MOCK_TEXT_INPUT === "1" ? "AXTextArea" : "AXButton";
  let elements = [
    { element_index: 0, element_token: sid + ":0", role: "AXWindow", label: "Test", value: null, selected: null, enabled: true, depth: 0, frame: { x: 100, y: 50, w: 800, h: 600 }, parent_index: null },
    { element_index: 1, element_token: sid + ":1", role: interactiveRole, label: process.env.MOCK_SHADOW_PLAY === "1" ? "NotPlay" : "Play", value: snaps > flipAfter ? "Playing" : null, selected: snaps > flipAfter, enabled: true, depth: 1, frame: { x: 200, y: 150, w: 40, h: 20 }, parent_index: 0 },
    { element_index: 3, element_token: sid + ":3", role: "AXStaticText", label: "Queue", value: null, selected: null, enabled: true, depth: 1, frame: { x: 200, y: 200, w: 60, h: 18 }, parent_index: 0 }
  ];
  if (process.env.MOCK_DUPLICATE_PLAY === "1") {
    elements.push({ element_index: 2, element_token: sid + ":2", role: "AXButton", label: "Play", value: null, selected: false, enabled: true, depth: 1, frame: { x: 260, y: 150, w: 40, h: 20 }, parent_index: 0 });
  }
  // 窗口被平铺窗口管理器推到屏幕外时，元素几何跟着窗口一起平移（现场：音乐窗口只剩 1px 可见）
  const bounds = process.env.MOCK_OFFSCREEN === "1"
    ? { x: 1919, y: 40, width: 948, height: 1030 }
    : process.env.MOCK_WINDOW_BOUNDS ? JSON.parse(process.env.MOCK_WINDOW_BOUNDS) : { x: 100, y: 50, width: 800, height: 600 };
  if (process.env.MOCK_OFFSCREEN === "1") {
    const dx = bounds.x - 100, dy = bounds.y - 50;
    elements = elements.map((el) => ({ ...el, frame: { ...el.frame, x: el.frame.x + dx, y: el.frame.y + dy } }));
  }
  // 动作后的那次采集里索引图已被替换：同一个元素换了号，身份（role+label）不变
  if (process.env.MOCK_SHIFT_INDEX === "1" && snaps > Number(process.env.MOCK_FLIP_AFTER ?? "1")) {
    elements = elements.map((el) => ({ ...el, element_index: el.element_index + 4, element_token: sid + ":" + (el.element_index + 4) }));
  }
  // 忠实复现驱动的 query 语义：只回命中项加祖先链，其余元素在响应里消失
  if (args.query) {
    const keep = new Set();
    for (const el of elements) {
      if ((el.role + " " + (el.label ?? "")).toLowerCase().includes(String(args.query).toLowerCase())) {
        keep.add(el.element_index);
        if (el.parent_index != null) keep.add(el.parent_index);
      }
    }
    elements = elements.filter((el) => keep.has(el.element_index));
  }
  console.log(JSON.stringify({
    pid: args.pid,
    window_id: args.window_id,
    snapshot_id: sid,
    returned_element_count: elements.length,
    total_element_count: elements.length,
    elements_complete: false,
    window_bounds: bounds,
    screenshot_file_path: pngPath,
    screenshot_width: pngPath ? 1200 : undefined,
    screenshot_height: pngPath ? 900 : undefined,
    screenshot_scale: 2,
    screenshot_frame_valid: true,
    elements,
    // markdown 是 elements 的超集：驱动只给可操作元素发索引，其余节点只在这里出现。
    tree_markdown: "- [0] AXWindow \\"Test\\"\\n  - [1] " + interactiveRole + " \\"Play\\" actions=[press]\\n  - [3] AXStaticText = \\"Queue\\""
      + (process.env.MOCK_TEXT_ONLY === "1" ? "\\n  - AXButton (上一首)" : "")
  }));
} else if (tool === "list_windows") {
  const windows = [
    { pid: 99, window_id: 3, app_name: "Front", title: "Front Win", z_index: 9, is_on_screen: true, on_current_space: true, bounds: { x: 0, y: 0, width: 1200, height: 800 } },
    { pid: 42, window_id: 7, app_name: "Test", title: "Test Win", z_index: 5, is_on_screen: true, on_current_space: true, bounds: { x: 100, y: 50, width: 800, height: 600 } },
    { pid: 7, window_id: 1, app_name: "Hidden", title: "Other Space", z_index: null, is_on_screen: false, on_current_space: false }
  ];
  if (process.env.MOCK_DUP_WINDOW === "1") windows.splice(2, 0, { pid: 42, window_id: 8, app_name: "Test", title: "Test Win 2", z_index: 3, is_on_screen: true, on_current_space: true, bounds: { x: 200, y: 100, width: 400, height: 300 } });
  console.log(JSON.stringify({ windows }));
} else if (tool === "get_screen_size") {
  console.log(JSON.stringify({ width: 1920, height: 1080, scale_factor: 1 }));
} else if (tool === "zoom") {
  writeImage(flagPath("--screenshot-out-file"));
  // 忠实复现驱动的裁剪语义：四周各加 20% 边距，加完仍超 500 px 宽时整体等比缩到 500
  const cw = (args.x2 - args.x1) * 1.4;
  const ch = (args.y2 - args.y1) * 1.4;
  const k = cw > 500 ? 500 / cw : 1;
  console.log(JSON.stringify({ content: [{ type: "image" }], width: Math.round(cw * k), height: Math.round(ch * k), format: "jpeg" }));
} else if (tool === "verify_state") {
  const status = process.env.MOCK_VERIFY_STATUS ?? "satisfied";
  console.log(JSON.stringify({
    stable: status === "satisfied",
    elapsed_ms: 12,
    samples: 2,
    predicates: [{ index: 0, status, unknown_reason: process.env.MOCK_VERIFY_REASON ?? (status === "unknown" ? "target_missing" : undefined), observed_json: { role: "AXButton", label: "Play" } }]
  }));
} else if (tool === "type_text") {
  console.log(JSON.stringify({ effect: "partial", path: "key_events", code: "type_text_incomplete", delivered_chars: 2, requested_chars: 5, retryable: true, retry_from_character: 2 }));
} else {
  console.log(JSON.stringify({ effect: process.env.MOCK_CLICK_EFFECT ?? "confirmed", route: "accessibility", delivery: { mode: "background" }, evidence: [{ kind: "value_readback" }] }));
}
`,
  );
  chmodSync(driver, 0o755);
  const env = { ...process.env, CUA_DRIVER: driver, COMPUTER_USE_CACHE_DIR: join(dir, "cache") };
  return { dir, env, log };
}

function run(env: Record<string, string | undefined>, args: string[]) {
  const result = Bun.spawnSync(["bun", cli, ...args], { env, stdout: "pipe", stderr: "pipe" });
  return {
    code: result.exitCode,
    stdout: result.stdout.toString(),
    stderr: result.stderr.toString(),
  };
}

// get_screen_size 是环境查询，不属于动作协议；断言动作序列时统一滤掉它。
function callsOf(log: string) {
  return readFileSync(log, "utf8")
    .trim()
    .split("\n")
    .map((line) => JSON.parse(line))
    .filter((call) => call.tool !== "get_screen_size");
}

describe("computer-use action protocol", () => {
  test("reuses the last snapshot token and reports structured action evidence", () => {
    const { env, log } = setup();
    expect(run(env, ["snapshot", "42:7"]).code).toBe(0);

    const action = run(env, ["click", "42:7", "t1"]);
    expect(action.code).toBe(0);
    expect(action.stdout).toContain("effect=confirmed");
    expect(action.stdout).toContain("route=accessibility");
    expect(action.stdout).toContain("evidence=value_readback");

    const calls = callsOf(log);
    // snapshot → click → 动作后重新采集
    expect(calls.map((call) => call.tool)).toEqual(["get_window_state", "click", "get_window_state"]);
    expect(calls[1].args.element_token).toBe("s00000001:1");
  });

  test("reports the post-action delta and refreshes the cached snapshot", () => {
    const { env, dir } = setup();
    expect(run(env, ["snapshot", "42:7"]).code).toBe(0);

    const action = run(env, ["click", "42:7", "t1"]);
    expect(action.code).toBe(0);
    expect(action.stdout).toContain("delta added=0 removed=0 changed=1");
    expect(action.stdout).toContain('~ Button Play ""->"Playing [sel]"');

    const cached = JSON.parse(readFileSync(join(dir, "cache", "42-7.json"), "utf8"));
    expect(cached.state.snapshot_id).toBe("s00000002"); // 采集两次：动作前一次、动作后一次
    expect(action.stdout).toContain(`observe: snapshot=${cached.state.snapshot_id} delta`);
    expect(cached.state.elements.find((el: { element_index: number }) => el.element_index === 1).value).toBe("Playing");
  });

  test("writes the observation PNG so the next pixel action has a fresh image", () => {
    const { env, dir } = setup();
    expect(run(env, ["snapshot", "42:7"]).code).toBe(0);
    const png = join(dir, "cache", "42-7.png");
    expect(existsSync(png)).toBe(false);

    expect(run(env, ["click", "42:7", "t1"]).code).toBe(0);
    expect(existsSync(png)).toBe(true);
    expect(readFileSync(png).length).toBeGreaterThan(0);
  });

  test("fails loudly when the driver reports a screenshot path but writes no image", () => {
    const { env, dir } = setup();
    const action = run({ ...env, MOCK_SKIP_IMAGE: "1" }, ["appshot", "42:7"]);

    expect(action.code).toBe(1);
    expect(action.stderr).toContain("未能取得有效图片");
    expect(existsSync(join(dir, "cache", "42-7.png"))).toBe(false);
  });

  test("appshot without any target refuses to guess and prints agent-friendly guidance", () => {
    const { env, log } = setup();
    const shot = run(env, ["appshot"]);

    expect(shot.code).toBe(1);
    expect(shot.stderr).toContain("没有可用目标");
    expect(shot.stderr).toContain("computer-use windows");
    expect(existsSync(log)).toBe(false); // 绝不隐式调用驱动工具猜测前台窗口
  });

  test("subcommands refuse missing target arguments with guided help", () => {
    const { env } = setup();
    const noArgs = run(env, []);
    expect(noArgs.code).toBe(0);
    expect(noArgs.stdout).toContain("闭环工作流 (SOP)");

    const clickNoTarget = run(env, ["click", "42:7"]);
    expect(clickNoTarget.code).toBe(1);
    expect(clickNoTarget.stderr).toContain("error: 'click' 缺少点击目标");
    expect(clickNoTarget.stderr).toContain("computer-use appshot 42:7");

    const openNoTarget = run(env, ["open"]);
    expect(openNoTarget.code).toBe(1);
    expect(openNoTarget.stderr).toContain("error: 'open' 命令必须指定应用名称");
    expect(openNoTarget.stderr).toContain("computer-use apps");
  });

  test("reports an unavailable production driver without leaking a runtime stack", () => {
    const { env, dir } = setup();
    const result = run({ ...env, CUA_DRIVER: join(dir, "missing-driver") }, ["windows"]);

    expect(result.code).toBe(1);
    expect(result.stderr).toContain("error: list_windows failed");
    expect(result.stderr).not.toContain("at cmdWindows");
  });

  test("computes the walk budget only when asked", () => {
    const { env, log } = setup();
    expect(run(env, ["appshot", "42:7", "--full"]).code).toBe(0);

    let calls = callsOf(log);
    let capture = calls.find((call) => call.tool === "get_window_state");
    expect(capture.args.max_depth).toBeUndefined();
    expect(capture.args.max_elements).toBeUndefined();

    // 省略预算时不下发任何上限，交给驱动默认值；这里的树只是一小片，回来的是同样的元素
    expect(run(env, ["snapshot", "42:7"]).code).toBe(0);
    calls = callsOf(log);
    capture = calls.filter((call) => call.tool === "get_window_state").pop();
    expect(capture.args.max_depth).toBeUndefined();
    expect(capture.args.max_elements).toBeUndefined();

    expect(run(env, ["snapshot", "42:7", "--depth", "5", "--max-elements", "120"]).code).toBe(0);
    calls = callsOf(log);
    capture = calls.filter((call) => call.tool === "get_window_state").pop();
    expect(capture.args.max_depth).toBe(5);
    expect(capture.args.max_elements).toBe(120);
  });

  test("reports the walk-completeness readings instead of a never-firing cut", () => {
    const { env } = setup();
    const out = run(env, ["snapshot", "42:7"]);

    expect(out.code).toBe(0);
    expect(out.stdout).toContain("shown=3 walked=3 tree=full unindexed=0");
    // 驱动的 total_element_count 恒等于 returned_element_count，cut= 的判据永不成立
    expect(out.stdout).not.toContain("cut=");
    expect(out.stdout).not.toContain("walked=3/3");
  });

  test("reports a depth wall when the deepest element stops at the requested depth", () => {
    const { env } = setup();

    const walled = run(env, ["snapshot", "42:7", "--depth", "1"]);
    expect(walled.code).toBe(0);
    expect(walled.stdout).toContain("tree=depth-limited(depth=1)");

    const deeper = run(env, ["snapshot", "42:7", "--depth", "4"]);
    expect(deeper.code).toBe(0);
    expect(deeper.stdout).toContain("tree=full");
  });

  test("surfaces a match that only exists in the tree markdown", () => {
    const { env } = setup();

    const indexed = run(env, ["find", "42:7", "Queue"]);
    expect(indexed.code).toBe(0);
    expect(indexed.stdout).toContain("unindexed=0");

    const textOnly = run({ ...env, MOCK_TEXT_ONLY: "1" }, ["find", "42:7", "上一首"]);
    expect(textOnly.code).toBe(0);
    expect(textOnly.stdout).toContain("shown=1");
    expect(textOnly.stdout).toContain("~\tButton\t上一首\tno-token");
    expect(textOnly.stdout).toContain("unindexed=1");
    // 改前这里会报「该窗口没有可操作元素」，把真实存在的文字说成不存在
    expect(textOnly.stdout).not.toContain("没有可操作元素");
    expect(textOnly.stdout).toContain("没有索引");
  });

  test("verifies a UI predicate through verify_state and echoes its verdict", () => {
    const { env, log } = setup();
    const verified = run(env, [
      "verify", "42:7", "AXButton", "Play", "value", "Playing",
    ]);

    expect(verified.code).toBe(0);
    expect(verified.stdout).toContain("verify: verdict=satisfied stable=true");
    expect(verified.stdout).toContain("observed=");

    const calls = callsOf(log);
    expect(calls[0]).toEqual({
      tool: "verify_state",
      args: {
        pid: 42,
        window_id: 7,
        timeout_ms: 5000,
        expect: [{ element: { selector: { role: "Button", label_contains: "Play" }, value_equals: "Playing" } }],
      },
    });
  });

  test("distinguishes unsatisfied from unknown when verifying", () => {
    const { env } = setup();
    const unsatisfied = run({ ...env, MOCK_VERIFY_STATUS: "unsatisfied" }, ["verify", "42:7", "Button", "Play", "selected", "true"]);
    expect(unsatisfied.code).toBe(1);
    expect(unsatisfied.stdout).toContain("verify: verdict=unsatisfied");

    const unknown = run({ ...env, MOCK_VERIFY_STATUS: "unknown" }, ["verify", "42:7", "Button", "Play", "exists"]);
    expect(unknown.code).toBe(2);
    expect(unknown.stdout).toContain("verify: verdict=unknown reason=target_missing");
  });

  test("refuses to verify when the selector matches several elements", () => {
    const { env, log } = setup();
    expect(run({ ...env, MOCK_DUPLICATE_PLAY: "1" }, ["snapshot", "42:7"]).code).toBe(0);

    const verified = run({ ...env, MOCK_DUPLICATE_PLAY: "1" }, ["verify", "42:7", "Button", "Play", "exists"]);
    expect(verified.code).toBe(1);
    expect(verified.stderr).toContain("选择器匹配 2 个元素");

    const calls = callsOf(log);
    expect(calls.some((call) => call.tool === "verify_state")).toBe(false);
  });

  test("explains a multi_match verdict from the driver's substring selector", () => {
    const { env } = setup();
    const multi = { ...env, MOCK_VERIFY_STATUS: "unknown", MOCK_VERIFY_REASON: "multi_match" };
    expect(run(multi, ["snapshot", "42:7"]).code).toBe(0);

    const voted = run(multi, ["verify", "42:7", "Button", "Play", "exists"]);

    expect(voted.code).toBe(2);
    expect(voted.stdout).toContain("verify: verdict=unknown reason=multi_match");
    expect(voted.stdout).toContain("note=驱动侧 selector 只有 label_contains");

    // 判定成功时不该出现这条 note
    expect(run(env, ["snapshot", "42:7"]).code).toBe(0);
    const ok = run(env, ["verify", "42:7", "Button", "Play", "exists"]);
    expect(ok.stdout).toContain("verify: verdict=satisfied");
    expect(ok.stdout).not.toContain("label_contains");
  });

  test("flags a substring match that is not the label the caller named", () => {
    const { env } = setup();
    const shadow = { ...env, MOCK_SHADOW_PLAY: "1" };
    expect(run(shadow, ["snapshot", "42:7"]).code).toBe(0);

    const verified = run(shadow, ["verify", "42:7", "Button", "Play", "exists"]);

    expect(verified.code).toBe(0);
    expect(verified.stdout).toContain('matched="NotPlay"');
    expect(verified.stdout).toContain("exact=false");
    expect(verified.stdout).toContain("note=label 未精确匹配");
  });

  test("reports partial text delivery with retry details", () => {
    const { env } = setup();
    const action = run(env, ["type", "42:7", "hello"]);

    expect(action.code).toBe(0);
    expect(action.stdout).toContain("effect=partial");
    expect(action.stdout).toContain("route=key_events");
    expect(action.stdout).toContain("chars=2/5 retryable=true retry_from=2");
    expect(action.stdout).toContain("state=partial");
  });

  test("passes screenshot pixel coordinates through unchanged", () => {
    const { env, log, dir } = setup();
    expect(run(env, ["snapshot", "42:7", "--screenshot", join(dir, "window.png")]).code).toBe(0);
    expect(run(env, ["click", "42:7", "500", "235"]).code).toBe(0);

    const calls = callsOf(log);
    expect(calls.map((call) => call.tool)).toEqual(["get_window_state", "click", "get_window_state"]);
    expect(calls[1]).toEqual({ tool: "click", args: { pid: 42, window_id: 7, x: 500, y: 235 } });
  });

  test("falls back to the text input center when its AX actions cannot click", () => {
    const { env, log } = setup();
    const textInputEnv = { ...env, MOCK_TEXT_INPUT: "1" };
    expect(run(textInputEnv, ["snapshot", "42:7"]).code).toBe(0);

    const action = run(textInputEnv, ["click", "42:7", "t1"]);

    expect(action.code).toBe(0);
    const calls = callsOf(log);
    expect(calls.map((call) => call.tool)).toEqual([
      "get_window_state",
      "get_window_state",
      "click",
      "get_window_state",
    ]);
    expect(calls[2]).toEqual({
      tool: "click",
      args: { pid: 42, window_id: 7, x: 180, y: 165 },
    });
  });

  test("refuses to focus a text input by pixels when the window sits off the screen", () => {
    const { env, log } = setup();
    const off = { ...env, MOCK_TEXT_INPUT: "1", MOCK_OFFSCREEN: "1" };
    expect(run(off, ["snapshot", "42:7"]).code).toBe(0);

    const action = run(off, ["click", "42:7", "t1"]);

    expect(action.code).toBe(1);
    expect(action.stderr).toContain("文本输入控件需要像素点击聚焦");
    expect(action.stderr).toContain("point lies outside window frame");
    expect(action.stderr).toContain("computer-use move");
    expect(callsOf(log).some((call) => call.tool === "click")).toBe(false);
  });

  test("warns but still delivers an explicit pixel click outside the visible area", () => {
    const { env, log } = setup();
    const off = { ...env, MOCK_OFFSCREEN: "1" };
    expect(run(off, ["appshot", "42:7"]).code).toBe(0);

    const action = run(off, ["click", "42:7", "500", "235"]);

    expect(action.code).toBe(0);
    expect(action.stdout).toContain("note=像素点 (500,235)");
    expect(action.stdout).toContain("落在窗口与屏幕的交集之外");
    expect(callsOf(log).some((call) => call.tool === "click")).toBe(true);
  });

  test("routes right-click to AXShowMenu on a token and to pixels on coordinates", () => {
    const { env, log, dir } = setup();
    expect(run(env, ["snapshot", "42:7", "--screenshot", join(dir, "window.png")]).code).toBe(0);
    expect(run(env, ["right-click", "42:7", "t1"]).code).toBe(0);
    expect(run(env, ["right-click", "42:7", "500", "235"]).code).toBe(0);

    const calls = callsOf(log);
    const rightClicks = calls.filter((call) => call.tool === "right_click");
    expect(rightClicks[0].args).toEqual({ pid: 42, window_id: 7, element_token: "s00000001:1" });
    expect(rightClicks[1].args).toEqual({ pid: 42, window_id: 7, x: 500, y: 235 });
  });

  test("sends a drag in the last screenshot's pixel space", () => {
    const { env, log, dir } = setup();
    expect(run(env, ["snapshot", "42:7", "--screenshot", join(dir, "window.png")]).code).toBe(0);
    expect(run(env, ["drag", "42:7", "10", "20", "300", "400"]).code).toBe(0);

    const calls = callsOf(log);
    expect(calls[1].tool).toBe("drag");
    expect(calls[1].args).toEqual({
      pid: 42,
      window_id: 7,
      from_x: 10,
      from_y: 20,
      to_x: 300,
      to_y: 400,
    });
  });

  test("lands the zoomed region image on disk for reading small text", () => {
    const { env, dir } = setup();
    expect(run(env, ["snapshot", "42:7", "--screenshot", join(dir, "window.png")]).code).toBe(0);
    const zoom = run(env, ["zoom", "42:7", "100", "120", "400", "260"]);

    expect(zoom.code).toBe(0);
    const jpg = join(dir, "cache", "42-7-zoom.jpg");
    expect(zoom.stdout).toContain(`zoom=${jpg}`);
    expect(existsSync(jpg)).toBe(true);
  });

  test("rejects an inverted zoom region instead of blaming the screenshot", () => {
    const { env, log } = setup();
    expect(run(env, ["appshot", "42:7"]).code).toBe(0);

    const zoom = run(env, ["zoom", "42:7", "1200", "600", "300", "80"]);

    expect(zoom.code).toBe(1);
    expect(zoom.stderr).toContain("x2>x1");
    expect(callsOf(log).some((call) => call.tool === "zoom")).toBe(false);
  });

  test("reports the region the driver actually captured instead of the requested one", () => {
    const { env, log } = setup();
    expect(run(env, ["appshot", "42:7"]).code).toBe(0);

    // 请求 100,120-400,260：驱动四周各加 20%（60,28），图片实际覆盖 40,92-460,288
    const zoom = run(env, ["zoom", "42:7", "100", "120", "400", "260"]);
    expect(zoom.code).toBe(0);
    expect(zoom.stdout).toContain("region=40,92 420x196 scale=1.19");
    expect(zoom.stdout).toContain("requested=(100,120)-(400,260)");
    // zoom 是唯一按原生像素收坐标的工具：窗口 800x600 点、截图 1200x900、screenshot_scale 2
    // ⇒ 换算比 2*800/1200 = 1.3333，下发前必须乘上去，否则截到的是别的位置
    expect(zoom.stdout).toContain("ratio=1.3333");
    expect(callsOf(log).find((call) => call.tool === "zoom")?.args).toEqual({ pid: 42, window_id: 7, x1: 133, y1: 160, x2: 533, y2: 347 });

    // ax= 是屏幕点：照抄进 zoom 会落在这张 1200x900 的图之外，必须拒绝而不是交回一张夹到边缘的图
    const outside = run(env, ["zoom", "42:7", "2222", "878", "2300", "930"]);
    expect(outside.code).toBe(1);
    expect(outside.stderr).toContain("必须在截图 PNG 内");
    expect(callsOf(log).filter((call) => call.tool === "zoom").length).toBe(1);
  });

  test("verifies element state change when --wait t<idx> is passed", () => {
    const { env, log } = setup();
    expect(run(env, ["snapshot", "42:7"]).code).toBe(0);

    // click with --wait t1; the mock driver returns updated value on poll
    const action = run(env, ["click", "42:7", "t1", "--wait", "t1"]);
    expect(action.code).toBe(0);
    expect(action.stdout).toContain("verify: target=t1 verdict=confirmed");
    expect(action.stdout).toContain("diff=");

    const calls = callsOf(log);
    // get_window_state (snapshot), click (act), get_window_state (poll)
    expect(calls.map((call) => call.tool)).toContain("click");
    expect(calls.filter((call) => call.tool === "get_window_state").length).toBeGreaterThanOrEqual(2);
  });

  test("waits on the element's identity when the post-action snapshot renumbered it", () => {
    const { env } = setup();
    const shift = { ...env, MOCK_SHIFT_INDEX: "1" };
    expect(run(shift, ["snapshot", "42:7"]).code).toBe(0);

    // 动作后的采集里 t1 变成 t5：只看索引必然找不到，必须按 role+label 找回同一个元素
    const action = run(shift, ["click", "42:7", "t1", "--wait", "t1"]);

    expect(action.code).toBe(0);
    expect(action.stdout).toContain("verify: target=t1 verdict=confirmed");
  });

  test("refuses a token minted by a snapshot the index map has already replaced", () => {
    const { env, log } = setup();
    expect(run(env, ["snapshot", "42:7"]).code).toBe(0);
    expect(run(env, ["click", "42:7", "t1"]).code).toBe(0);

    // 动作自带一次重采，索引图已被替换：同一个 t1 已经不再指向那个元素
    const stale = run(env, ["click", "42:7", "t1"]);
    expect(stale.code).toBe(1);
    expect(stale.stderr).toContain("来自快照");
    expect(stale.stderr).toContain("请重新 appshot/find 取 token");

    // 驱动限定形式同理：写明快照的 token 与当前快照不符就是过期
    const mismatched = run(env, ["click", "42:7", "s00000001:1"]);
    expect(mismatched.code).toBe(1);
    expect(mismatched.stderr).toContain("不是当前快照");

    expect(callsOf(log).filter((call) => call.tool === "click").length).toBe(1); // 两次都被拦在投递之前

    // 重新取 token 立刻恢复可用，护栏不制造无谓拒绝
    expect(run(env, ["snapshot", "42:7"]).code).toBe(0);
    expect(run(env, ["click", "42:7", "t1"]).code).toBe(0);
  });

  test("verifies media status when --wait media:playing is passed, and ignores media-control when omitted", () => {
    const { env, dir } = setup();
    const mockMedia = join(dir, "mock-media-control.ts");
    const mediaLog = join(dir, "media-calls.log");
    writeFileSync(
      mockMedia,
      `#!/usr/bin/env bun
import { appendFileSync } from "node:fs";
appendFileSync(${JSON.stringify(mediaLog)}, "called\\n");
console.log(JSON.stringify({ playing: true, title: "Test Song", artist: "Artist", bundleIdentifier: "com.test.player" }));
`,
    );
    chmodSync(mockMedia, 0o755);
    const testEnv = { ...env, MEDIA_CONTROL_BIN: mockMedia };

    expect(run(testEnv, ["snapshot", "42:7"]).code).toBe(0);

    // Case 1: normal click without --wait: media-control must NEVER be executed
    expect(run(testEnv, ["click", "42:7", "t1"]).code).toBe(0);
    expect(existsSync(mediaLog)).toBe(false);

    // Case 2: explicit --wait media:playing: media-control is executed and verified
    // 上一次动作已经重采过快照，索引图被替换，同一批 token 必须重新取
    expect(run(testEnv, ["snapshot", "42:7"]).code).toBe(0);
    const action = run(testEnv, ["click", "42:7", "t1", "--wait", "media:playing"]);
    expect(action.code).toBe(0);
    expect(action.stdout).toContain("verify: target=media:playing verdict=confirmed");
    // media: 等的是系统级 now-playing，不是目标窗口那个应用，必须报出实际播放器
    expect(action.stdout).toContain("app=com.test.player");
    expect(readFileSync(mediaLog, "utf8").trim()).toBe("called");
  });

  test("distinguishes a broken media tool from an unobservable media state", () => {
    const { env, dir } = setup();

    expect(run(env, ["snapshot", "42:7"]).code).toBe(0);
    const missing = run({ ...env, MEDIA_CONTROL_BIN: join(dir, "no-such-media-control") }, ["click", "42:7", "t1", "--wait", "media:playing"]);
    expect(missing.code).toBe(1);
    expect(missing.stderr).toContain("媒体状态工具未找到");
    expect(missing.stdout).not.toContain("timeout");

    // 上一次动作已经重采过快照，索引图被替换，同一批 token 必须重新取
    expect(run(env, ["snapshot", "42:7"]).code).toBe(0);
    // /bin/false 在 macOS 上不存在，用真实存在但必然失败的可执行文件才能触发「执行失败」这条路
    const broken = run({ ...env, MEDIA_CONTROL_BIN: "/usr/bin/false" }, ["click", "42:7", "t1", "--wait", "media:playing"]);
    expect(broken.code).toBe(1);
    expect(broken.stderr).toContain("媒体状态工具执行失败");
    expect(broken.stdout).not.toContain("timeout");
  });

  test("exits with code 2 when --wait times out without expected change", () => {
    const { env } = setup();
    expect(run(env, ["snapshot", "42:7"]).code).toBe(0);

    // wait on t0 (AXWindow) which never changes in mock driver
    const action = run(env, ["click", "42:7", "t1", "--wait", "t0", "--timeout", "300"]);
    expect(action.code).toBe(2);
    expect(action.stdout).toContain("verify: target=t0 verdict=timeout");
  });

  test("targets specific element token when key t<idx> is passed", () => {
    const { env, log } = setup();
    expect(run(env, ["snapshot", "42:7"]).code).toBe(0);

    const action = run(env, ["key", "42:7", "t1", "return"]);
    expect(action.code).toBe(0);

    const calls = callsOf(log);
    expect(calls[1]).toEqual({
      tool: "press_key",
      args: { pid: 42, window_id: 7, element_token: "s00000001:1", key: "return" },
    });
  });

  test("routes modified keys through hotkey", () => {
    const { env, log } = setup();
    const textInputEnv = { ...env, MOCK_TEXT_INPUT: "1" };
    expect(run(textInputEnv, ["snapshot", "42:7"]).code).toBe(0);

    const action = run(textInputEnv, ["key", "42:7", "t1", "s", "cmd", "--foreground"]);

    expect(action.code).toBe(0);
    // 前置聚焦那次点击是独立投递，必须单独可见，否则调用方只看到 hotkey 那一半
    expect(action.stdout).toContain("prefocus click: effect=confirmed");
    expect(action.stdout).toContain("hotkey: effect=confirmed");
    const calls = callsOf(log);
    expect(calls.map((call) => call.tool)).toEqual([
      "get_window_state",
      "get_window_state",
      "click",
      "hotkey",
      "get_window_state",
    ]);
    expect(calls[2]).toEqual({
      tool: "click",
      args: { pid: 42, window_id: 7, x: 180, y: 165 },
    });
    expect(calls[3]).toEqual({
      tool: "hotkey",
      args: {
        pid: 42,
        window_id: 7,
        keys: ["cmd", "s"],
        delivery_mode: "foreground",
      },
    });
  });
});

describe("target addressing and read-path cost", () => {
  test("windows prints copy-ready targets with geometry and viewport state", () => {
    const { env } = setup();
    const out = run(env, ["windows"]);

    expect(out.code).toBe(0);
    expect(out.stdout).toContain("TARGET\tZ\tAPP\tTITLE\tBOUNDS\tSTATE");
    expect(out.stdout).toContain("42:7\t5\tTest\tTest Win\t100,50 800x600\tok");
    expect(out.stdout).not.toContain("Hidden"); // 默认只列使用者眼前的窗口

    const all = run(env, ["windows", "--all"]);
    expect(all.stdout).toContain("7:1\t-\tHidden");
    expect(all.stdout).toContain("hidden,other-space");
  });

  test("resolves a target by app name and reuses it for the next command", () => {
    const { env, log } = setup();
    const shot = run(env, ["snapshot", "Test"]);

    expect(shot.code).toBe(0);
    expect(shot.stdout).toContain("target=42:7");

    expect(run(env, ["click", "t1"]).code).toBe(0);
    const clicks = callsOf(log).filter((c) => c.tool === "click");
    expect(clicks.pop().args).toMatchObject({ pid: 42, window_id: 7 });
  });

  test("takes the frontmost window and reports how many candidates matched", () => {
    const { env } = setup();
    const out = run({ ...env, MOCK_DUP_WINDOW: "1" }, ["snapshot", "Test"]);

    expect(out.code).toBe(0);
    expect(out.stdout).toContain("target=42:7"); // z=5 高于 z=3
    expect(out.stdout).toContain("2 个窗口匹配 'Test'");
  });

  test("find projects the walk to the matches plus their ancestors", () => {
    const { env } = setup();
    const out = run(env, ["find", "42:7", "Play"]);

    expect(out.code).toBe(0);
    expect(out.stdout).toContain('find="Play"');
    expect(out.stdout).toContain("shown=2");
    expect(out.stdout).toContain("t1\tButton\tPlay");
    expect(out.stdout).toContain("t0\tWindow\tTest"); // 祖先链跟着留下
  });

  test("marks find rows as match or ancestor so token extraction is unambiguous", () => {
    const { env } = setup();
    const out = run(env, ["find", "42:7", "Play"]);

    expect(out.code).toBe(0);
    expect(out.stdout).toMatch(/^t1\tButton\tPlay\t.*\tmatch$/m);
    expect(out.stdout).toMatch(/^t0\tWindow\tTest\t.*\tancestor$/m);
    // 祖先与命中混在一起时，取第一个 token 会拿到祖先，必须只有一行可当命中
    expect(out.stdout.match(/^t\d+\t.*\tmatch$/gm)?.length).toBe(1);
  });

  test("falls back to the sticky target when the first argument is not an addressable app", () => {
    const { env, log } = setup();
    expect(run(env, ["snapshot", "Test"]).code).toBe(0);

    // SKILL.md 自己给的例子：Button 是角色名，不是应用名
    const verified = run(env, ["verify", "Button", "Play", "exists"]);
    expect(verified.code).toBe(0);
    expect(callsOf(log).pop()?.tool).toBe("verify_state");

    const found = run(env, ["find", "Play"]);
    expect(found.code).toBe(0);
    expect(found.stdout).toContain('find="Play"');

    // 没有粘性目标时必须如实报错，而不是把匹配词吃掉后静默失败
    const clean = setup();
    const orphan = run(clean.env, ["find", "Play"]);
    expect(orphan.code).toBe(1);
    expect(orphan.stderr).toContain("没有可用目标");
  });

  test("keeps the full snapshot as the baseline after a projected find", () => {
    const { env } = setup();
    const flip = { ...env, MOCK_FLIP_AFTER: "2" };
    expect(run(flip, ["snapshot", "42:7"]).code).toBe(0);
    expect(run(flip, ["find", "42:7", "Play"]).code).toBe(0);

    const action = run(flip, ["click", "42:7", "t1"]);

    expect(action.code).toBe(0);
    // 基线是 find 之前那份完整快照，所以投影丢掉的其他元素不会被误报成新增
    expect(action.stdout).toContain("delta added=0 removed=0 changed=1");
    expect(action.stdout).not.toContain("baseline=none");
  });

  test("flags a window the screen edge cuts instead of letting a pixel action fail later", () => {
    const { env } = setup();
    const clipped = run({ ...env, MOCK_WINDOW_BOUNDS: JSON.stringify({ x: 1919, y: 40, width: 948, height: 1030 }) }, ["snapshot", "42:7"]);
    expect(clipped.stdout).toContain("clipped");

    const outside = run({ ...env, MOCK_WINDOW_BOUNDS: JSON.stringify({ x: 3000, y: 40, width: 948, height: 1030 }) }, ["snapshot", "42:7"]);
    expect(outside.stdout).toContain("off-viewport");
    expect(outside.stdout).toContain("computer-use move");
  });

  test("keeps pixel coordinates usable across a tree-only snapshot and invalidates them when the window moves", () => {
    const { env } = setup();
    expect(run(env, ["appshot", "42:7"]).code).toBe(0);
    expect(run(env, ["find", "42:7", "Play"]).code).toBe(0);

    // find 不截图，但它不该把 appshot 留下的像素凭证作废
    expect(run(env, ["click", "42:7", "500", "235"]).code).toBe(0);

    // 窗口被挪走后 PNG 里的几何已经不对，必须拒绝而不是照旧投递
    const moved = { ...env, MOCK_WINDOW_BOUNDS: JSON.stringify({ x: 500, y: 300, width: 800, height: 600 }) };
    expect(run(moved, ["find", "42:7", "Play"]).code).toBe(0);
    const stale = run(moved, ["click", "42:7", "500", "235"]);
    expect(stale.code).toBe(1);
    expect(stale.stderr).toContain("窗口几何已变化");
  });

  test("keeps the action verdict when the window disappears before observation", () => {
    const { env } = setup();
    expect(run(env, ["snapshot", "42:7"]).code).toBe(0);

    const action = run({ ...env, MOCK_WINDOW_GONE: "1" }, ["click", "42:7", "t1"]);

    expect(action.code).toBe(0);
    expect(action.stdout).toContain("effect=confirmed");
    expect(action.stdout).toContain("observe: unavailable");
  });

  test("reports a driver refusal as a refusal instead of a broken tree", () => {
    const { env } = setup();
    const denied = run({ ...env, MOCK_REFUSAL_STDOUT: "1" }, ["snapshot", "42:7"]);

    expect(denied.code).toBe(1);
    expect(denied.stderr).toContain("驱动拒绝 get_window_state：protected_resource_scope_invalid");
    expect(denied.stderr).toContain("not a directory");
    expect(denied.stderr).not.toContain("无效 elements");
  });

  test("hints that an unverifiable action with an unchanged tree proves nothing", () => {
    const { env } = setup();
    const silent = { ...env, MOCK_CLICK_EFFECT: "unverifiable", MOCK_FLIP_AFTER: "999" };
    expect(run(silent, ["snapshot", "42:7"]).code).toBe(0);

    const action = run(silent, ["click", "42:7", "t1"]);

    expect(action.code).toBe(0);
    expect(action.stdout).toContain("state=delivered_unverified");
    expect(action.stdout).toContain("hint=动作已投递但 AX 树没有任何变化：本次 click");
  });

  test("names the delivery tool in the no-receipt hint instead of always blaming click", () => {
    const { env } = setup();
    const silent = { ...env, MOCK_CLICK_EFFECT: "unverifiable", MOCK_FLIP_AFTER: "999" };
    expect(run(silent, ["snapshot", "42:7"]).code).toBe(0);

    const action = run(silent, ["key", "42:7", "t1", "escape"]);

    expect(action.code).toBe(0);
    expect(action.stdout).toContain("hint=动作已投递但 AX 树没有任何变化：本次 press_key");
  });
});
