import { afterEach, describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const SCRIPT = resolve(import.meta.dir, "../skills/subagent-policy/spawn-subagent");
const PLUGIN_HOOKS = resolve(import.meta.dir, "agy-plugin/hooks.json");

const tempDirs: string[] = [];

function makeHome(): string {
  const dir = mkdtempSync(join(tmpdir(), "spawn-subagent-test-"));
  tempDirs.push(dir);
  mkdirSync(join(dir, ".pi/agent/agents"), { recursive: true });
  mkdirSync(join(dir, ".omp/agent"), { recursive: true });
  writeFileSync(join(dir, ".pi/agent/settings.json"), JSON.stringify({ packages: [] }, null, 2));
  return dir;
}

function writeMd(home: string, name: string, role: string, tools: string, body = `Role prompt for ${name}`) {
  writeFileSync(
    join(home, ".pi/agent/agents", `${name}.md`),
    `---\ndescription: "Desc ${name}"\nrole: ${role}\ntools: ${tools}\n---\n\n${body}\n`,
  );
}

function writeOmpConfig(home: string, yaml: string) {
  writeFileSync(join(home, ".omp/agent/config.yml"), yaml);
}

function runScript(args: string[], env: Record<string, string> = {}, input?: string) {
  return spawnSync(process.execPath, [SCRIPT, ...args], {
    encoding: "utf8",
    env: { ...process.env, ...env },
    input,
  });
}

afterEach(() => {
  while (tempDirs.length) {
    rmSync(tempDirs.pop()!, { recursive: true, force: true });
  }
});

describe("agy model resolution in list", () => {
  test("resolves agy/<family>:<effort>, aliases, overrides, and rejects unsupported efforts", () => {
    const home = makeHome();
    writeMd(home, "reviewer-agy", "reviewer-agy", "read,bash,grep,intercom");
    writeMd(home, "task-agy", "reviewer-agy", "read,bash,edit,write,intercom");
    writeMd(home, "scout-agy", "scout-agy", "read,grep,intercom");
    writeMd(home, "bad-agy", "bad-agy", "read,intercom");
    writeMd(home, "reviewer-ds", "reviewer-ds", "read,grep,intercom");

    writeOmpConfig(
      home,
      [
        "modelRoles:",
        "  reviewer-agy: agy/gemini-4-carbon:high",
        "  scout-agy: agy/hydrogen:xhigh",
        "  bad-agy: agy/carbon:xhigh",
        "  reviewer-ds: mp/loomy/DeepSeek-V4.1-Flash:high",
        "task:",
        "  agentModelOverrides:",
        "    task-agy: agy/hydrogen:high",
      ].join("\n") + "\n",
    );

    const res = runScript(["list", "--json"], { HOME: home });
    expect(res.status).toBe(0);
    const items = JSON.parse(res.stdout);
    const byName = Object.fromEntries(items.map((x: any) => [x.name, x]));

    expect(byName["reviewer-agy"]).toMatchObject({
      name: "reviewer-agy",
      runner: "agy",
      access: "ro",
      model: "agy/gemini-4-carbon-high",
      thinking: "high",
    });
    expect(byName["task-agy"]).toMatchObject({
      name: "task-agy",
      runner: "agy",
      access: "rw",
      model: "agy/gemini-4-hydrogen-high",
      thinking: "high",
    });
    expect(byName["scout-agy"]).toMatchObject({
      name: "scout-agy",
      runner: "agy",
      access: "ro",
      model: "agy/gemini-4-hydrogen-xhigh",
      thinking: "xhigh",
    });
    expect(byName["bad-agy"].error).toContain("agy");
    expect(byName["reviewer-ds"]).toMatchObject({
      name: "reviewer-ds",
      runner: "pi",
      access: "ro",
      model: "mp/loomy/DeepSeek-V4.1-Flash",
      thinking: "high",
    });
  });
});

function installFakeIntercom(home: string, location: "pi" | "omp" = "pi"): string {
  const inbox = join(home, "intercom-inbox.jsonl");
  const dir =
    location === "pi"
      ? join(home, ".pi/agent/npm/node_modules/pi-intercom")
      : join(home, ".omp/plugins/node_modules/pi-intercom");
  mkdirSync(dir, { recursive: true });
  writeFileSync(
    join(dir, "cli.ts"),
    `import { appendFileSync } from "node:fs";\nappendFileSync(${JSON.stringify(inbox)}, JSON.stringify(process.argv.slice(2)) + "\\n");\n`,
  );
  return inbox;
}

function runPluginHook(
  event: "SessionStart" | "Stop",
  payload: unknown,
  env: Record<string, string>,
) {
  const hooksDoc = JSON.parse(readFileSync(PLUGIN_HOOKS, "utf8"));
  const cmd: string = hooksDoc["spawn-subagent"][event][0].command;
  return spawnSync("/bin/sh", ["-c", cmd], {
    encoding: "utf8",
    env: { ...process.env, ...env },
    input: JSON.stringify(payload),
  });
}

describe("agy lifecycle hooks (SessionStart & Stop)", () => {
  test("short-circuits to {} when SPAWN_SUBAGENT_META is unset", () => {
    const home = makeHome();
    const env: Record<string, string> = { HOME: home, SPAWN_SUBAGENT_META: "" };
    const s1 = runPluginHook("SessionStart", { conversationId: "c1" }, env);
    expect(s1.status).toBe(0);
    expect(JSON.parse(s1.stdout)).toEqual({});

    const s2 = runPluginHook("Stop", { conversationId: "c1", fullyIdle: true }, env);
    expect(s2.status).toBe(0);
    expect(JSON.parse(s2.stdout)).toEqual({});
  });

  test("injects system prompt once on root SessionStart, ignores child subagents, and delivers untruncated final turn via OMP intercom fallback across resume turns", () => {
    const home = makeHome();
    const inbox = installFakeIntercom(home, "omp");
    const txDir = join(home, "brain/conv-root/.system_generated/logs");
    mkdirSync(txDir, { recursive: true });
    const txCompact = join(txDir, "transcript.jsonl");
    const txFull = join(txDir, "transcript_full.jsonl");
    const sysFile = join(home, "reviewer-agy.md");
    writeFileSync(sysFile, "你是严格的代码审查员。\n");

    const metaFile = join(home, "meta.json");
    writeFileSync(
      metaFile,
      JSON.stringify({
        agentName: "reviewer-agy-auth-abc",
        to: "parent-omp-session-1",
        systemFile: sysFile,
      }),
    );

    const hookEnv = {
      HOME: home,
      SPAWN_SUBAGENT_META: metaFile,
      SPAWN_SUBAGENT_BUN: process.execPath,
      SPAWN_SUBAGENT_BIN: SCRIPT,
    };

    // 1. Root SessionStart locks rootConversationId & injects system prompt
    const startRoot = runPluginHook(
      "SessionStart",
      { conversationId: "conv-root", transcriptPath: txCompact },
      hookEnv,
    );
    expect(startRoot.status).toBe(0);
    expect(JSON.parse(startRoot.stdout)).toEqual({
      injectSteps: [{ systemMessage: { systemMessage: "你是严格的代码审查员。" } }],
    });
    expect(JSON.parse(readFileSync(metaFile, "utf8"))).toMatchObject({
      rootConversationId: "conv-root",
      transcriptPath: txCompact,
    });

    // 2. Nested agy subagent SessionStart is ignored and does not overwrite rootConversationId
    const startChild = runPluginHook(
      "SessionStart",
      { conversationId: "conv-child", transcriptPath: "/other/transcript.jsonl" },
      hookEnv,
    );
    expect(startChild.status).toBe(0);
    expect(JSON.parse(startChild.stdout)).toEqual({});
    expect(JSON.parse(readFileSync(metaFile, "utf8")).rootConversationId).toBe("conv-root");

    // Write Turn 1 transcript: compact is truncated, full has intermediate tool call + final Markdown report
    const turn1Lines = [
      JSON.stringify({ step_index: 0, type: "USER_INPUT", status: "DONE", content: "审查 auth.ts" }),
      JSON.stringify({
        step_index: 1,
        type: "PLANNER_RESPONSE",
        status: "DONE",
        content: "先读取 auth.ts。",
        tool_calls: [{ name: "read_file" }],
      }),
      JSON.stringify({ step_index: 2, type: "GENERIC", status: "DONE", content: "file body" }),
      JSON.stringify({
        step_index: 3,
        type: "PLANNER_RESPONSE",
        status: "DONE",
        content: "发现 1 个越权漏洞：`auth.ts:42` 未校验租户 ID（完整未截断正文）。",
      }),
    ];
    writeFileSync(txCompact, JSON.stringify({ step_index: 3, type: "PLANNER_RESPONSE", status: "DONE", content: "truncated..." }) + "\n");
    writeFileSync(txFull, turn1Lines.join("\n") + "\n");

    // 3. Ignored stops: child conversation, not fullyIdle, USER_CANCELED
    runPluginHook("Stop", { conversationId: "conv-child", transcriptPath: txCompact, fullyIdle: true, terminationReason: "NO_TOOL_CALL" }, hookEnv);
    runPluginHook("Stop", { conversationId: "conv-root", transcriptPath: txCompact, fullyIdle: false, terminationReason: "NO_TOOL_CALL" }, hookEnv);
    runPluginHook("Stop", { conversationId: "conv-root", transcriptPath: txCompact, fullyIdle: true, terminationReason: "USER_CANCELED" }, hookEnv);
    expect(existsSync(inbox)).toBe(false);

    // 4. Real root Stop delivers untruncated Turn 1 final response via intercom
    const stop1 = runPluginHook(
      "Stop",
      { conversationId: "conv-root", transcriptPath: txCompact, fullyIdle: true, terminationReason: "NO_TOOL_CALL" },
      hookEnv,
    );
    expect(stop1.status).toBe(0);
    expect(JSON.parse(stop1.stdout)).toEqual({});
    const deliveries1 = readFileSync(inbox, "utf8").trim().split("\n").map((l) => JSON.parse(l));
    expect(deliveries1).toEqual([
      [
        "send",
        "--to",
        "parent-omp-session-1",
        "--name",
        "reviewer-agy-auth-abc",
        "--text",
        "[reviewer-agy-auth-abc]\n发现 1 个越权漏洞：`auth.ts:42` 未校验租户 ID（完整未截断正文）。",
      ],
    ]);

    // 5. Duplicate Stop on same step is deduplicated
    runPluginHook(
      "Stop",
      { conversationId: "conv-root", transcriptPath: txCompact, fullyIdle: true, terminationReason: "NO_TOOL_CALL" },
      hookEnv,
    );
    expect(readFileSync(inbox, "utf8").trim().split("\n")).toHaveLength(1);

    // 6. Turn 2 (resume) appends new USER_INPUT + PLANNER_RESPONSE and delivers cleanly
    const turn2Lines = [
      ...turn1Lines,
      JSON.stringify({ step_index: 4, type: "USER_INPUT", status: "DONE", content: "复核修复补丁" }),
      JSON.stringify({ step_index: 5, type: "PLANNER_RESPONSE", status: "DONE", content: "补丁已修复越权问题，LGTM。" }),
    ];
    writeFileSync(txFull, turn2Lines.join("\n") + "\n");
    runPluginHook(
      "Stop",
      { conversationId: "conv-root", transcriptPath: txCompact, fullyIdle: true, terminationReason: "NO_TOOL_CALL" },
      hookEnv,
    );
    const deliveries2 = readFileSync(inbox, "utf8").trim().split("\n").map((l) => JSON.parse(l));
    expect(deliveries2).toHaveLength(2);
    expect(deliveries2[1][6]).toBe("[reviewer-agy-auth-abc]\n补丁已修复越权问题，LGTM。");
  });
});

function makeFakeBinDir(home: string): { binDir: string; logPath: string } {
  const binDir = join(home, "bin");
  const logPath = join(home, "calls.jsonl");
  mkdirSync(binDir, { recursive: true });
  return { binDir, logPath };
}

function writeExecutable(dir: string, name: string, jsBody: string) {
  const file = join(dir, name);
  writeFileSync(file, `#!/usr/bin/env bun\n${jsBody}\n`);
  chmodSync(file, 0o755);
}

describe("dispatching agy across hc, kitty (under OMP env), and herdr", () => {
  test("hc: batch dispatches ro (--mode plan) and rw agy profiles without sec-run, passes healthGate, and differentiates resume", () => {
    const home = makeHome();
    const { binDir, logPath } = makeFakeBinDir(home);
    const stateFile = join(home, "hc-state.json");
    writeFileSync(stateFile, JSON.stringify({ seq: 1, terms: { t1: { address: "t1", state: "live", labels: {} } } }));

    writeMd(home, "reviewer-agy", "reviewer-agy", "read,bash,grep,intercom", "Reviewer body");
    writeMd(home, "task-agy", "reviewer-agy", "read,bash,edit,write,intercom", "Task body");
    writeMd(home, "reviewer-ds", "reviewer-ds", "read,grep,intercom", "Pi reviewer body");
    writeOmpConfig(
      home,
      [
        "modelRoles:",
        "  reviewer-agy: agy/carbon:high",
        "  reviewer-ds: mp/loomy/DeepSeek-V4.1-Flash:high",
        "task:",
        "  agentModelOverrides:",
        "    task-agy: agy/hydrogen:high",
      ].join("\n") + "\n",
    );

    writeExecutable(
      binDir,
      "hc",
      `
import { appendFileSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
const args = process.argv.slice(2);
appendFileSync(${JSON.stringify(logPath)}, JSON.stringify({ bin: "hc", args }) + "\\n");
const st = JSON.parse(readFileSync(${JSON.stringify(stateFile)}, "utf8"));
if (args[0] === "get") {
  const id = args.at(-1)!;
  const t = st.terms[id];
  if (!t) process.exit(3);
  console.log(JSON.stringify(t));
} else if (args[0] === "run") {
  const id = "t" + (++st.seq);
  const labels: Record<string, string> = {};
  let parent = "";
  let name = "";
  for (let i = 1; i < args.length; i++) {
    if (args[i] === "--") { args.splice(0, i + 1); break; }
    if (args[i] === "--label") { const [k, v] = args[++i].split("="); labels[k] = v; }
    else if (args[i] === "--parent") parent = args[++i];
    else if (args[i] === "--name") name = args[++i];
  }
  st.terms[id] = { address: id, name, parent, state: "live", labels, created_ms: Date.now() };
  writeFileSync(${JSON.stringify(stateFile)}, JSON.stringify(st));
  // Simulate agy writing SessionStart meta + healthy transcript (with a benign GENERIC ERROR tool step first)
  const metaArg = args.find((a) => a.startsWith("SPAWN_SUBAGENT_META="));
  if (metaArg) {
    const metaFile = metaArg.slice("SPAWN_SUBAGENT_META=".length);
    const txDir = join(${JSON.stringify(home)}, "tx", id);
    mkdirSync(txDir, { recursive: true });
    const txFile = join(txDir, "transcript.jsonl");
    const meta = JSON.parse(readFileSync(metaFile, "utf8"));
    meta.rootConversationId = "conv-" + id;
    meta.transcriptPath = txFile;
    writeFileSync(metaFile, JSON.stringify(meta));
    writeFileSync(txFile, [
      JSON.stringify({ step_index: 0, type: "USER_INPUT", status: "DONE", content: "hi" }),
      JSON.stringify({ step_index: 1, type: "GENERIC", status: "ERROR", error: "tool hiccup" }),
      JSON.stringify({ step_index: 2, type: "PLANNER_RESPONSE", status: "DONE", content: "ok" }),
    ].join("\\n") + "\\n");
  } else {
    // Simulate pi writing healthy session jsonl
    const sidIdx = args.indexOf("--session-id");
    if (sidIdx >= 0) {
      const sid = args[sidIdx + 1];
      const sdir = join(${JSON.stringify(home)}, ".pi/agent-subagent/sessions/--cwd--");
      mkdirSync(sdir, { recursive: true });
      writeFileSync(join(sdir, "1_" + sid + ".jsonl"), JSON.stringify({ type: "message", message: { role: "assistant", stopReason: "stop" } }) + "\\n");
    }
  }
  console.log(JSON.stringify({ address: id }));
} else if (args[0] === "send") {
  console.log(JSON.stringify({ ok: true }));
} else if (args[0] === "kill" || args[0] === "rm") {
  const id = args.at(-1)!;
  if (args[0] === "kill" && st.terms[id]) st.terms[id].state = "finished";
  if (args[0] === "rm") delete st.terms[id];
  writeFileSync(${JSON.stringify(stateFile)}, JSON.stringify(st));
  console.log(JSON.stringify({ ok: true }));
}
`,
    );

    const manifest = join(home, "batch.json");
    writeFileSync(
      manifest,
      JSON.stringify({
        task: "检查模块边界",
        agents: [
          { profile: "reviewer-agy", slug: "rev" },
          { profile: "task-agy", slug: "impl" },
          { profile: "reviewer-ds", slug: "pi-rev" },
        ],
      }),
    );

    const env = {
      HOME: home,
      PATH: `${binDir}:${process.env.PATH}`,
      HC_TERMINAL_ID: "t1",
      PI_INTERCOM_SESSION_ID: "omp-main-99",
    };

    const batchRes = runScript(["batch", manifest, "--json"], env);
    expect(batchRes.status).toBe(0);
    const out = JSON.parse(batchRes.stdout);
    expect(out).toEqual([
      { profile: "reviewer-agy", id: "t2", status: "ok" },
      { profile: "task-agy", id: "t3", status: "ok" },
      { profile: "reviewer-ds", id: "t4", status: "ok" },
    ]);

    const calls = readFileSync(logPath, "utf8").trim().split("\n").map((l) => JSON.parse(l));
    const runCalls = calls.filter((c) => c.args[0] === "run");
    // reviewer-agy: agy (no sec-run), --model gemini-4-carbon-high, --mode plan, --dangerously-skip-permissions
    expect(runCalls[0].args).toContain("agy");
    expect(runCalls[0].args).not.toContain("sec-run");
    expect(runCalls[0].args).toContain("gemini-4-carbon-high");
    expect(runCalls[0].args).toContain("plan");
    expect(runCalls[0].args).toContain("--dangerously-skip-permissions");
    // task-agy: rw -> no --mode plan
    expect(runCalls[1].args).toContain("gemini-4-hydrogen-high");
    expect(runCalls[1].args).not.toContain("plan");
    // reviewer-ds: pi -> uses sec-run
    expect(runCalls[2].args).toContain("sec-run");

    // Resume agy vs pi
    expect(runScript(["resume", "t2", "--", "复查第 10 行"], env).status).toBe(0);
    expect(runScript(["resume", "t4", "--", "复查第 20 行"], env).status).toBe(0);
    const sendCalls = readFileSync(logPath, "utf8").trim().split("\n").map((l) => JSON.parse(l)).filter((c) => c.args[0] === "send");
    expect(sendCalls[0].args.at(-1)).not.toContain("intercom({");
    expect(sendCalls[0].args.at(-1)).toContain("复查第 10 行");
    expect(sendCalls[1].args.at(-1)).toContain("omp-main-99");
  });

  test("hc: agy pre-session AGY_ERROR 429 in --log-file fails healthGate as config-error and auto-closes terminal", () => {
    const home = makeHome();
    const { binDir, logPath } = makeFakeBinDir(home);
    const stateFile = join(home, "hc-state.json");
    writeFileSync(stateFile, JSON.stringify({ terms: { t1: { address: "t1", state: "live" } } }));

    writeMd(home, "reviewer-agy", "reviewer-agy", "read,intercom");
    writeOmpConfig(home, "modelRoles:\n  reviewer-agy: agy/carbon:high\n");

    writeExecutable(
      binDir,
      "hc",
      `
import { appendFileSync, readFileSync, writeFileSync } from "node:fs";
const args = process.argv.slice(2);
appendFileSync(${JSON.stringify(logPath)}, JSON.stringify({ bin: "hc", args }) + "\\n");
const st = JSON.parse(readFileSync(${JSON.stringify(stateFile)}, "utf8"));
if (args[0] === "get") {
  const id = args.at(-1)!;
  if (!st.terms[id]) process.exit(3);
  console.log(JSON.stringify(st.terms[id]));
} else if (args[0] === "run") {
  const logIdx = args.indexOf("--log-file");
  if (logIdx >= 0) {
    writeFileSync(args[logIdx + 1], 'AGY_ERROR: {"status":"RESOURCE_EXHAUSTED","error_code":429}\\n');
  }
  st.terms["t2"] = { address: "t2", parent: "t1", state: "finished", labels: {} };
  writeFileSync(${JSON.stringify(stateFile)}, JSON.stringify(st));
  console.log(JSON.stringify({ address: "t2" }));
} else if (args[0] === "kill" || args[0] === "rm") {
  console.log(JSON.stringify({ ok: true }));
}
`,
    );

    const res = runScript(["reviewer-agy", "quota", "--", "审查"], {
      HOME: home,
      PATH: `${binDir}:${process.env.PATH}`,
      HC_TERMINAL_ID: "t1",
      PI_INTERCOM_SESSION_ID: "sid-1",
    });
    expect(res.status).toBe(1);
    expect(res.stderr).toContain("config-error:");
    expect(res.stderr).toContain("RESOURCE_EXHAUSTED");
    const calls = readFileSync(logPath, "utf8").trim().split("\n").map((l) => JSON.parse(l));
    expect(calls.some((c) => c.args[0] === "kill" && c.args.includes("t2"))).toBe(true);
    expect(calls.some((c) => c.args[0] === "rm" && c.args.includes("t2"))).toBe(true);
  });

  test("kitty under OMP bash env (TERM=dumb, CI=true) sanitizes TUI env vars and launches agy", () => {
    const home = makeHome();
    const { binDir, logPath } = makeFakeBinDir(home);
    const winState = join(home, "kitty.json");
    writeFileSync(winState, JSON.stringify([{ tabs: [{ layout: "splits", windows: [{ id: 1, lines: 40, user_vars: {} }] }] }]));

    writeMd(home, "reviewer-agy", "reviewer-agy", "read,intercom");
    writeOmpConfig(home, "modelRoles:\n  reviewer-agy: agy/hydrogen:medium\n");

    writeExecutable(
      binDir,
      "kitten",
      `
import { appendFileSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
const args = process.argv.slice(2);
appendFileSync(${JSON.stringify(logPath)}, JSON.stringify({ bin: "kitten", args }) + "\\n");
const st = JSON.parse(readFileSync(${JSON.stringify(winState)}, "utf8"));
if (args[1] === "ls") {
  console.log(JSON.stringify(st));
} else if (args[1] === "launch") {
  st[0].tabs[0].windows.push({ id: 9, lines: 40, user_vars: { subagent: "1" } });
  writeFileSync(${JSON.stringify(winState)}, JSON.stringify(st));
  const metaArg = args.find((a) => a.startsWith("SPAWN_SUBAGENT_META="));
  if (metaArg) {
    const metaFile = metaArg.slice("SPAWN_SUBAGENT_META=".length);
    const txDir = join(${JSON.stringify(home)}, "kitty-tx");
    mkdirSync(txDir, { recursive: true });
    const txFile = join(txDir, "transcript.jsonl");
    const meta = JSON.parse(readFileSync(metaFile, "utf8"));
    meta.transcriptPath = txFile;
    writeFileSync(metaFile, JSON.stringify(meta));
    writeFileSync(txFile, JSON.stringify({ step_index: 1, type: "PLANNER_RESPONSE", status: "DONE", content: "ok" }) + "\\n");
  }
  console.log("9");
}
`,
    );

    const res = runScript(["reviewer-agy", "omp-kitty", "--", "检查"], {
      HOME: home,
      PATH: `${binDir}:${process.env.PATH}`,
      HC_TERMINAL_ID: "",
      HERDR_PANE_ID: "",
      KITTY_WINDOW_ID: "1",
      PI_INTERCOM_SESSION_ID: "omp-sid",
      TERM: "dumb",
      NO_COLOR: "1",
      CI: "true",
    });
    expect(res.status).toBe(0);
    expect(res.stdout.trim()).toBe("9");

    const launchCall = readFileSync(logPath, "utf8").trim().split("\n").map((l) => JSON.parse(l)).find((c) => c.args[1] === "launch");
    expect(launchCall.args).toContain("TERM=xterm-kitty");
    expect(launchCall.args).toContain("COLORTERM=truecolor");
    expect(launchCall.args).toContain("NO_COLOR=");
    expect(launchCall.args).toContain("CI=");
    expect(launchCall.args).toContain("agy");
  });

  test("herdr (legacy): starts agy with --kind agy and injects prompt via herdr agent prompt", () => {
    const home = makeHome();
    const { binDir, logPath } = makeFakeBinDir(home);

    writeMd(home, "reviewer-agy", "reviewer-agy", "read,intercom");
    writeOmpConfig(home, "modelRoles:\n  reviewer-agy: agy/argon:high\n");

    writeExecutable(
      binDir,
      "herdr",
      `
import { appendFileSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
const args = process.argv.slice(2);
appendFileSync(${JSON.stringify(logPath)}, JSON.stringify({ bin: "herdr", args }) + "\\n");
if (args[0] === "pane" && args[1] === "get") {
  console.log(JSON.stringify({ result: { pane: { pane_id: "w1:p1" } } }));
} else if (args[0] === "pane" && args[1] === "layout") {
  console.log(JSON.stringify({ result: { layout: { panes: [{ pane_id: "w1:p1", rect: { x: 0, y: 0 } }, { pane_id: "w1:p2", rect: { x: 100, y: 0 } }], splits: [] } } }));
} else if (args[0] === "pane" && args[1] === "split") {
  console.log(JSON.stringify({ result: { pane: { pane_id: "w1:p2" } } }));
} else if (args[0] === "pane" && args[1] === "run") {
  const m = args[3].match(/SPAWN_SUBAGENT_META='([^']+)'/);
  if (m) {
    const metaFile = m[1];
    const txDir = join(${JSON.stringify(home)}, "herdr-tx");
    mkdirSync(txDir, { recursive: true });
    const txFile = join(txDir, "transcript.jsonl");
    const meta = JSON.parse(readFileSync(metaFile, "utf8"));
    meta.transcriptPath = txFile;
    writeFileSync(metaFile, JSON.stringify(meta));
    writeFileSync(txFile, JSON.stringify({ step_index: 1, type: "PLANNER_RESPONSE", status: "DONE", content: "ok" }) + "\\n");
  }
  console.log(JSON.stringify({ result: {} }));
} else if (args[0] === "agent" && args[1] === "start") {
  console.log(JSON.stringify({ result: { agent: {} } }));
} else if (args[0] === "agent" && args[1] === "prompt") {
  console.log(JSON.stringify({ type: "agent_prompted" }));
}
`,
    );

    const res = runScript(["reviewer-agy", "legacy", "--", "审查"], {
      HOME: home,
      PATH: `${binDir}:${process.env.PATH}`,
      HC_TERMINAL_ID: "",
      HERDR_PANE_ID: "w1:p1",
      KITTY_WINDOW_ID: "",
      PI_INTERCOM_SESSION_ID: "sid-herdr",
    });
    expect(res.status).toBe(0);
    expect(res.stdout.trim()).toBe("w1:p2");

    const calls = readFileSync(logPath, "utf8").trim().split("\n").map((l) => JSON.parse(l));
    const startCall = calls.find((c) => c.args[0] === "agent" && c.args[1] === "start");
    expect(startCall.args).toContain("--kind");
    expect(startCall.args[startCall.args.indexOf("--kind") + 1]).toBe("agy");
    expect(startCall.args).toContain("gemini-4-argon-high");
  });
});


