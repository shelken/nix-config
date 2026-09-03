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
import { appendFileSync, readFileSync } from "node:fs";
const [, , command, tool, rawArgs] = process.argv;
const args = JSON.parse(rawArgs);
appendFileSync(${JSON.stringify(log)}, JSON.stringify({ tool, args }) + "\\n");
const calls = readFileSync(${JSON.stringify(log)}, "utf8").trim().split("\\n").length;
if (command !== "call") process.exit(2);
if (tool === "get_window_state") {
  console.log(JSON.stringify({
    pid: args.pid,
    window_id: args.window_id,
    snapshot_id: "s" + calls.toString(16).padStart(8, "0"),
    returned_element_count: 2,
    total_element_count: 2,
    elements_complete: true,
    window_bounds: { x: 100, y: 50, width: 800, height: 600 },
    screenshot_file_path: args.screenshot_out_file,
    screenshot_width: args.screenshot_out_file ? 1200 : undefined,
    screenshot_height: args.screenshot_out_file ? 900 : undefined,
    elements: [
      { element_index: 0, element_token: "s" + calls.toString(16).padStart(8, "0") + ":0", role: "AXWindow", label: "Test", value: null, selected: null, enabled: true, frame: { x: 100, y: 50, w: 800, h: 600 }, parent_index: null },
      { element_index: 1, element_token: "s" + calls.toString(16).padStart(8, "0") + ":1", role: "AXButton", label: "Play", value: calls >= 3 ? "Playing" : null, selected: calls >= 3, enabled: true, frame: { x: 200, y: 150, w: 40, h: 20 }, parent_index: 0 }
    ],
    tree_markdown: "- [0] AXWindow \\\"Test\\\"\\n  - [1] AXButton \\\"Play\\\" actions=[press]"
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
    expect(calls.map((call) => call.tool)).toEqual(["get_window_state", "click"]);
    expect(calls[1].args.element_token).toBe("s00000001:1");
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
    expect(calls.map((call) => call.tool)).toEqual(["get_window_state", "click"]);
    expect(calls[1]).toEqual({ tool: "click", args: { pid: 42, window_id: 7, x: 500, y: 235 } });
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
});
