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
  const pngPath = args.screenshot_out_file ?? flagPath("--screenshot-out-file");
  writeImage(pngPath);
  const sid = "s" + calls.toString(16).padStart(8, "0");
  const interactiveRole = process.env.MOCK_TEXT_INPUT === "1" ? "AXTextArea" : "AXButton";
  const elements = [
    { element_index: 0, element_token: sid + ":0", role: "AXWindow", label: "Test", value: null, selected: null, enabled: true, frame: { x: 100, y: 50, w: 800, h: 600 }, parent_index: null },
    { element_index: 1, element_token: sid + ":1", role: interactiveRole, label: "Play", value: calls >= 3 ? "Playing" : null, selected: calls >= 3, enabled: true, frame: { x: 200, y: 150, w: 40, h: 20 }, parent_index: 0 }
  ];
  if (process.env.MOCK_DUPLICATE_PLAY === "1") {
    elements.push({ element_index: 2, element_token: sid + ":2", role: "AXButton", label: "Play", value: null, selected: false, enabled: true, frame: { x: 260, y: 150, w: 40, h: 20 }, parent_index: 0 });
  }
  console.log(JSON.stringify({
    pid: args.pid,
    window_id: args.window_id,
    snapshot_id: sid,
    returned_element_count: elements.length,
    total_element_count: elements.length,
    elements_complete: true,
    window_bounds: { x: 100, y: 50, width: 800, height: 600 },
    screenshot_file_path: pngPath,
    screenshot_width: pngPath ? 1200 : undefined,
    screenshot_height: pngPath ? 900 : undefined,
    elements,
    tree_markdown: "- [0] AXWindow \\"Test\\"\\n  - [1] " + interactiveRole + " \\"Play\\" actions=[press]"
  }));
} else if (tool === "list_windows") {
  console.log(JSON.stringify({ windows: [
    { pid: 99, window_id: 3, app_name: "Front", title: "Front Win", z_index: 9, is_on_screen: true, on_current_space: true, bounds: { x: 0, y: 0, width: 1200, height: 800 } },
    { pid: 42, window_id: 7, app_name: "Test", title: "Test Win", z_index: 5, is_on_screen: true, on_current_space: true, bounds: { x: 100, y: 50, width: 800, height: 600 } },
    { pid: 7, window_id: 1, app_name: "Hidden", title: "Other Space", z_index: null, is_on_screen: false, on_current_space: false }
  ] }));
} else if (tool === "get_screen_size") {
  console.log(JSON.stringify({ width: 1920, height: 1080, scale_factor: 1 }));
} else if (tool === "zoom") {
  writeImage(flagPath("--screenshot-out-file"));
  console.log(JSON.stringify({ content: [{ type: "image" }] }));
} else if (tool === "verify_state") {
  const status = process.env.MOCK_VERIFY_STATUS ?? "satisfied";
  console.log(JSON.stringify({
    stable: status === "satisfied",
    elapsed_ms: 12,
    samples: 2,
    predicates: [{ index: 0, status, unknown_reason: status === "unknown" ? "target_missing" : undefined, observed_json: { role: "AXButton", label: "Play" } }]
  }));
} else if (tool === "type_text") {
  console.log(JSON.stringify({ effect: "partial", path: "key_events", code: "type_text_incomplete", delivered_chars: 2, requested_chars: 5, retryable: true, retry_from_character: 2 }));
} else {
  console.log(JSON.stringify({ effect: "confirmed", route: "accessibility", delivery: { mode: "background" }, evidence: [{ kind: "value_readback" }] }));
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

describe("computer-use action protocol", () => {
  test("reuses the last snapshot token and reports structured action evidence", () => {
    const { env, log } = setup();
    expect(run(env, ["snapshot", "42", "7"]).code).toBe(0);

    const action = run(env, ["click", "42", "7", "t1"]);
    expect(action.code).toBe(0);
    expect(action.stdout).toContain("effect=confirmed");
    expect(action.stdout).toContain("route=accessibility");
    expect(action.stdout).toContain("evidence=value_readback");

    const calls = readFileSync(log, "utf8").trim().split("\n").map((line) => JSON.parse(line));
    // snapshot → click → 动作后重新采集
    expect(calls.map((call) => call.tool)).toEqual(["get_window_state", "click", "get_window_state"]);
    expect(calls[1].args.element_token).toBe("s00000001:1");
  });

  test("reports the post-action delta and refreshes the cached snapshot", () => {
    const { env, dir } = setup();
    expect(run(env, ["snapshot", "42", "7"]).code).toBe(0);

    const action = run(env, ["click", "42", "7", "t1"]);
    expect(action.code).toBe(0);
    expect(action.stdout).toContain("observe: snapshot=s00000003 delta added=0 removed=0 changed=1");
    expect(action.stdout).toContain('~ Button Play ""->"Playing [sel]"');

    const cached = JSON.parse(readFileSync(join(dir, "cache", "42-7.json"), "utf8"));
    expect(cached.state.snapshot_id).toBe("s00000003");
  });

  test("writes the observation PNG so the next pixel action has a fresh image", () => {
    const { env, dir } = setup();
    expect(run(env, ["snapshot", "42", "7"]).code).toBe(0);
    const png = join(dir, "cache", "42-7.png");
    expect(existsSync(png)).toBe(false);

    expect(run(env, ["click", "42", "7", "t1"]).code).toBe(0);
    expect(existsSync(png)).toBe(true);
    expect(readFileSync(png).length).toBeGreaterThan(0);
  });

  test("fails loudly when the driver reports a screenshot path but writes no image", () => {
    const { env, dir } = setup();
    const action = run({ ...env, MOCK_SKIP_IMAGE: "1" }, ["appshot", "42", "7"]);

    expect(action.code).toBe(1);
    expect(action.stderr).toContain("未能取得有效图片");
    expect(existsSync(join(dir, "cache", "42-7.png"))).toBe(false);
  });

  test("appshot without pid/wid refuses to guess and prints agent-friendly guidance", () => {
    const { env, log } = setup();
    const shot = run(env, ["appshot"]);

    expect(shot.code).toBe(1);
    expect(shot.stderr).toContain("error: 'appshot' 必须显式指定目标窗口的整数 <pid> 和 <wid>");
    expect(shot.stderr).toContain("computer-use windows");
    expect(existsSync(log)).toBe(false); // 绝不隐式调用驱动工具猜测前台窗口
  });

  test("subcommands refuse missing target arguments with guided help", () => {
    const { env } = setup();
    const noArgs = run(env, []);
    expect(noArgs.code).toBe(0);
    expect(noArgs.stdout).toContain("闭环工作流 (SOP)");

    const clickNoTarget = run(env, ["click", "42", "7"]);
    expect(clickNoTarget.code).toBe(1);
    expect(clickNoTarget.stderr).toContain("error: 'click' 缺少点击目标");
    expect(clickNoTarget.stderr).toContain("computer-use appshot 42 7");

    const openNoTarget = run(env, ["open"]);
    expect(openNoTarget.code).toBe(1);
    expect(openNoTarget.stderr).toContain("error: 'open' 命令必须指定应用名称");
    expect(openNoTarget.stderr).toContain("computer-use apps");
  });

  test("reports an unavailable production driver without leaking a runtime stack", () => {
    const { env, dir } = setup();
    const result = run({ ...env, CUA_DRIVER: join(dir, "missing-driver") }, ["windows"]);

    expect(result.code).toBe(1);
    expect(result.stderr).toContain("error: get_accessibility_tree failed");
    expect(result.stderr).not.toContain("at cmdWindows");
  });

  test("appshot --full asks the driver for an unbounded walk", () => {
    const { env, log } = setup();
    expect(run(env, ["appshot", "42", "7", "--full"]).code).toBe(0);

    let calls = readFileSync(log, "utf8").trim().split("\n").map((line) => JSON.parse(line));
    let capture = calls.find((call) => call.tool === "get_window_state");
    expect(capture.args.max_depth).toBeUndefined();
    expect(capture.args.max_elements).toBeUndefined();

    expect(run(env, ["appshot", "42", "7"]).code).toBe(0);
    calls = readFileSync(log, "utf8").trim().split("\n").map((line) => JSON.parse(line));
    capture = calls.filter((call) => call.tool === "get_window_state").pop();
    expect(capture.args.max_depth).toBe(3);
    expect(capture.args.max_elements).toBe(300);
  });

  test("verifies a UI predicate through verify_state and echoes its verdict", () => {
    const { env, log } = setup();
    const verified = run(env, [
      "verify", "42", "7", "AXButton", "Play", "value", "Playing",
    ]);

    expect(verified.code).toBe(0);
    expect(verified.stdout).toContain("verify: verdict=satisfied stable=true");
    expect(verified.stdout).toContain("observed=");

    const calls = readFileSync(log, "utf8").trim().split("\n").map((line) => JSON.parse(line));
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
    const unsatisfied = run({ ...env, MOCK_VERIFY_STATUS: "unsatisfied" }, ["verify", "42", "7", "Button", "Play", "selected", "true"]);
    expect(unsatisfied.code).toBe(1);
    expect(unsatisfied.stdout).toContain("verify: verdict=unsatisfied");

    const unknown = run({ ...env, MOCK_VERIFY_STATUS: "unknown" }, ["verify", "42", "7", "Button", "Play", "exists"]);
    expect(unknown.code).toBe(2);
    expect(unknown.stdout).toContain("verify: verdict=unknown reason=target_missing");
  });

  test("refuses to verify when the selector matches several elements", () => {
    const { env, log } = setup();
    expect(run({ ...env, MOCK_DUPLICATE_PLAY: "1" }, ["snapshot", "42", "7"]).code).toBe(0);

    const verified = run({ ...env, MOCK_DUPLICATE_PLAY: "1" }, ["verify", "42", "7", "Button", "Play", "exists"]);
    expect(verified.code).toBe(1);
    expect(verified.stderr).toContain("选择器匹配 2 个元素");

    const calls = readFileSync(log, "utf8").trim().split("\n").map((line) => JSON.parse(line));
    expect(calls.some((call) => call.tool === "verify_state")).toBe(false);
  });

  test("reports partial text delivery with retry details", () => {
    const { env } = setup();
    const action = run(env, ["type", "42", "7", "hello"]);

    expect(action.code).toBe(0);
    expect(action.stdout).toContain("effect=partial");
    expect(action.stdout).toContain("route=key_events");
    expect(action.stdout).toContain("chars=2/5 retryable=true retry_from=2");
    expect(action.stdout).toContain("state=partial");
  });

  test("passes screenshot pixel coordinates through unchanged", () => {
    const { env, log, dir } = setup();
    expect(run(env, ["snapshot", "42", "7", "--screenshot", join(dir, "window.png")]).code).toBe(0);
    expect(run(env, ["click", "42", "7", "500", "235"]).code).toBe(0);

    const calls = readFileSync(log, "utf8").trim().split("\n").map((line) => JSON.parse(line));
    expect(calls.map((call) => call.tool)).toEqual(["get_window_state", "click", "get_window_state"]);
    expect(calls[1]).toEqual({ tool: "click", args: { pid: 42, window_id: 7, x: 500, y: 235 } });
  });

  test("falls back to the text input center when its AX actions cannot click", () => {
    const { env, log } = setup();
    const textInputEnv = { ...env, MOCK_TEXT_INPUT: "1" };
    expect(run(textInputEnv, ["snapshot", "42", "7"]).code).toBe(0);

    const action = run(textInputEnv, ["click", "42", "7", "t1"]);

    expect(action.code).toBe(0);
    const calls = readFileSync(log, "utf8").trim().split("\n").map((line) => JSON.parse(line));
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

  test("routes right-click to AXShowMenu on a token and to pixels on coordinates", () => {
    const { env, log, dir } = setup();
    expect(run(env, ["snapshot", "42", "7", "--screenshot", join(dir, "window.png")]).code).toBe(0);
    expect(run(env, ["right-click", "42", "7", "t1"]).code).toBe(0);
    expect(run(env, ["right-click", "42", "7", "500", "235"]).code).toBe(0);

    const calls = readFileSync(log, "utf8").trim().split("\n").map((line) => JSON.parse(line));
    const rightClicks = calls.filter((call) => call.tool === "right_click");
    expect(rightClicks[0].args).toEqual({ pid: 42, window_id: 7, element_token: "s00000001:1" });
    expect(rightClicks[1].args).toEqual({ pid: 42, window_id: 7, x: 500, y: 235 });
  });

  test("sends a drag in the last screenshot's pixel space", () => {
    const { env, log, dir } = setup();
    expect(run(env, ["snapshot", "42", "7", "--screenshot", join(dir, "window.png")]).code).toBe(0);
    expect(run(env, ["drag", "42", "7", "10", "20", "300", "400"]).code).toBe(0);

    const calls = readFileSync(log, "utf8").trim().split("\n").map((line) => JSON.parse(line));
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
    expect(run(env, ["snapshot", "42", "7", "--screenshot", join(dir, "window.png")]).code).toBe(0);
    const zoom = run(env, ["zoom", "42", "7", "100", "120", "400", "260"]);

    expect(zoom.code).toBe(0);
    const jpg = join(dir, "cache", "42-7-zoom.jpg");
    expect(zoom.stdout).toContain(`zoom=${jpg}`);
    expect(existsSync(jpg)).toBe(true);
  });

  test("verifies element state change when --wait t<idx> is passed", () => {
    const { env, log } = setup();
    expect(run(env, ["snapshot", "42", "7"]).code).toBe(0);

    // click with --wait t1; the mock driver returns updated value on poll
    const action = run(env, ["click", "42", "7", "t1", "--wait", "t1"]);
    expect(action.code).toBe(0);
    expect(action.stdout).toContain("verify: target=t1 verdict=confirmed");
    expect(action.stdout).toContain("diff=");

    const calls = readFileSync(log, "utf8").trim().split("\n").map((line) => JSON.parse(line));
    // get_window_state (snapshot), click (act), get_window_state (poll)
    expect(calls.map((call) => call.tool)).toContain("click");
    expect(calls.filter((call) => call.tool === "get_window_state").length).toBeGreaterThanOrEqual(2);
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
console.log(JSON.stringify({ playing: true, title: "Test Song", artist: "Artist" }));
`,
    );
    chmodSync(mockMedia, 0o755);
    const testEnv = { ...env, MEDIA_CONTROL_BIN: mockMedia };

    expect(run(testEnv, ["snapshot", "42", "7"]).code).toBe(0);

    // Case 1: normal click without --wait: media-control must NEVER be executed
    expect(run(testEnv, ["click", "42", "7", "t1"]).code).toBe(0);
    expect(existsSync(mediaLog)).toBe(false);

    // Case 2: explicit --wait media:playing: media-control is executed and verified
    const action = run(testEnv, ["click", "42", "7", "t1", "--wait", "media:playing"]);
    expect(action.code).toBe(0);
    expect(action.stdout).toContain("verify: target=media:playing verdict=confirmed");
    expect(readFileSync(mediaLog, "utf8").trim()).toBe("called");
  });

  test("exits with code 2 when --wait times out without expected change", () => {
    const { env } = setup();
    expect(run(env, ["snapshot", "42", "7"]).code).toBe(0);

    // wait on t0 (AXWindow) which never changes in mock driver
    const action = run(env, ["click", "42", "7", "t1", "--wait", "t0", "--timeout", "300"]);
    expect(action.code).toBe(2);
    expect(action.stdout).toContain("verify: target=t0 verdict=timeout");
  });

  test("targets specific element token when key t<idx> is passed", () => {
    const { env, log } = setup();
    expect(run(env, ["snapshot", "42", "7"]).code).toBe(0);

    const action = run(env, ["key", "42", "7", "t1", "return"]);
    expect(action.code).toBe(0);

    const calls = readFileSync(log, "utf8").trim().split("\n").map((line) => JSON.parse(line));
    expect(calls[1]).toEqual({
      tool: "press_key",
      args: { pid: 42, window_id: 7, element_token: "s00000001:1", key: "return" },
    });
  });

  test("routes modified keys through hotkey", () => {
    const { env, log } = setup();
    const textInputEnv = { ...env, MOCK_TEXT_INPUT: "1" };
    expect(run(textInputEnv, ["snapshot", "42", "7"]).code).toBe(0);

    const action = run(textInputEnv, ["key", "42", "7", "t1", "s", "cmd", "--foreground"]);

    expect(action.code).toBe(0);
    const calls = readFileSync(log, "utf8").trim().split("\n").map((line) => JSON.parse(line));
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
