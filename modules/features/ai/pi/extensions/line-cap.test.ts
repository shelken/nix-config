import { afterAll, expect, test } from "bun:test";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import lineCap, { capMessage, capToolResult, MAX_BYTES, MAX_COLUMNS } from "./line-cap.ts";

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "line-cap-test-"));
afterAll(() => fs.rmSync(tmp, { recursive: true, force: true }));

const save = () => "/spill/x.txt";
const write = (name: string, text: string) => {
	const file = path.join(tmp, name);
	fs.writeFileSync(file, text);
	return file;
};
const text = (patch: { content: { text?: string }[] } | undefined) => patch?.content[0].text ?? "";

test("capToolResult：超长行截短不切开代理对，超限多行保留头尾并标出省略行数", () => {
	const surrogate = capToolResult(
		{ toolName: "bash", content: [{ type: "text", text: `${"a".repeat(MAX_COLUMNS - 1)}😀x` }] },
		save,
	);
	expect(text(surrogate).startsWith(`${"a".repeat(MAX_COLUMNS - 1)}…[+3 chars]\n\n[line-cap:`)).toBe(true);

	const lines = Array.from({ length: 3000 }, (_, i) => `L${i} ${"y".repeat(74)}`);
	const patch = capToolResult({ toolName: "bash", content: [{ type: "text", text: lines.join("\n") }] }, save);
	const body = text(patch).split("\n\n[line-cap:")[0];
	const out = body.split("\n");
	expect(out[0]).toBe(lines[0]);
	expect(out.at(-1)).toBe(lines.at(-1));
	const omitted = out.find((line) => /^\[… \d+ lines omitted …\]$/.test(line));
	expect(omitted).toBeDefined();
	expect(Number(omitted?.match(/\d+/)?.[0]) + out.length - 1).toBe(3000);
	expect(Buffer.byteLength(body)).toBeLessThanOrEqual(MAX_BYTES + 100);
});

test("capToolResult：大文件只读两端并丢掉边缘半截行，单个超长行只留开头", () => {
	const lines = Array.from({ length: 20000 }, (_, i) => `L${i} ${"y".repeat(74)}`);
	const big = write("big.log", `${lines.join("\n")}\n`);
	const bigPatch = capToolResult(
		{
			toolName: "bash",
			content: [{ type: "text", text: "tail" }],
			details: { truncation: { truncated: true, totalLines: 20000 }, fullOutputPath: big },
		},
		save,
	);
	const bigOut = text(bigPatch).split("\n\n[line-cap:")[0].split("\n");
	expect(bigOut[0]).toBe(lines[0]);
	expect(bigOut.at(-1)).toBe(lines.at(-1));
	expect(bigOut.some((line) => /^\[… \d+ lines omitted …\]$/.test(line))).toBe(true);

	const giant = write("giant.log", `START${"z".repeat(2_000_000)}END\n`);
	const giantPatch = capToolResult(
		{
			toolName: "bash",
			content: [{ type: "text", text: "tail" }],
			details: { truncation: { truncated: true, totalLines: 1 }, fullOutputPath: giant },
		},
		save,
	);
	expect(text(giantPatch).startsWith("START")).toBe(true);
});

test("capToolResult：pi 已截尾的 bash 输出按完整文件重排，开头、结尾、每行行首都在，退出状态保留", () => {
	const rows = Array.from({ length: 15 }, (_, i) => `ROW_START_${i + 1} ${"x".repeat(30000)} ROW_END_${i + 1}`);
	const full = write("incident.log", `${["HEAD_MARKER", ...rows, "TAIL_MARKER"].join("\n")}\n`);
	const piText = `${rows[14]}\nTAIL_MARKER\n\n[Showing lines 16-17 of 17 (50.0KB limit). Full output: ${full}]\n\nCommand exited with code 3`;
	const patch = capToolResult(
		{
			toolName: "bash",
			content: [{ type: "text", text: piText }],
			details: { truncation: { truncated: true, totalLines: 17 }, fullOutputPath: full },
			structuredContent: { exit_code: 3 },
		},
		save,
	);
	const out = text(patch);
	expect(out.startsWith("HEAD_MARKER\n")).toBe(true);
	expect(out).toContain("\nTAIL_MARKER\n");
	expect(out.match(/ROW_START_\d+ /g)?.length).toBe(15);
	expect(Math.max(...out.split("\n").map((line) => line.length))).toBeLessThan(MAX_COLUMNS + 200);
	expect(out).not.toContain("[Showing lines");
	expect(out.endsWith(`Full output: ${full}]\n\nCommand exited with code 3`)).toBe(true);
	expect(patch?.structuredContent).toEqual({ exit_code: 3 });
});

test("capToolResult：短输出、非 bash 工具不处理；完整文件读不到时退回处理现有文本", () => {
	expect(capToolResult({ toolName: "bash", content: [{ type: "text", text: "ok\n" }] }, save)).toBeUndefined();
	expect(capToolResult({ toolName: "read", content: [{ type: "text", text: "x".repeat(5000) }] }, save)).toBeUndefined();

	const patch = capToolResult(
		{
			toolName: "bash",
			content: [{ type: "text", text: `a\n${"x".repeat(3000)}` }],
			details: { truncation: { truncated: true, totalLines: 9 }, fullOutputPath: path.join(tmp, "missing.log") },
		},
		save,
	);
	expect(text(patch)).toContain("…[+2232 chars]");
	expect(text(patch).endsWith("Full output: /spill/x.txt]")).toBe(true);
});

test("capMessage：只处理后台结果消息和进上下文的 !cmd，同一输入两次结果逐字节相同", () => {
	const long = `Background job finished: bg1\nLast lines:\n${"q".repeat(5000)}`;
	const job = { role: "custom", customType: "background-job", content: long };
	const once = capMessage(job, save);
	expect((once.content as string).length).toBeLessThan(1000);
	expect(capMessage(job, save).content).toBe(once.content as string);

	const other = { role: "custom", customType: "other", content: long };
	expect(capMessage(other, save)).toBe(other);
	const excluded = { role: "bashExecution", output: long, excludeFromContext: true };
	expect(capMessage(excluded, save)).toBe(excluded);
	expect(capMessage({ role: "bashExecution", output: long }, save).output?.length).toBeLessThan(1000);
});

test("capToolResult：尾部窗口只剩超长行被清空时，回退用头部填满预算并在末尾标出省略行", () => {
	const lines = Array.from({ length: 3000 }, (_, i) => `L${i} ${"y".repeat(94)}`);
	const giant = "GIANT " + "z".repeat(300 * 1024);
	const full = write("tail-giant.log", `${[...lines, giant].join("\n")}\n`);
	const patch = capToolResult(
		{
			toolName: "bash",
			content: [{ type: "text", text: "tail" }],
			details: { truncation: { truncated: true, totalLines: 3001 }, fullOutputPath: full },
		},
		save,
	);
	const body = text(patch).split("\n\n[line-cap:")[0];
	const out = body.split("\n");
	expect(out[0]).toBe(lines[0]);
	expect(out.length).toBeGreaterThan(400);
	expect(Buffer.byteLength(body)).toBeGreaterThan(40 * 1024);
	expect(out.at(-1)).toMatch(/^\[… \d+ lines omitted …\]$/);
});

test("capMessage：!cmd 截断输出回读 fullOutputPath 找回开头，与 tool_result 一致", () => {
	const rows = Array.from({ length: 15 }, (_, i) => `ROW_START_${i + 1} ${"x".repeat(30000)} ROW_END_${i + 1}`);
	const full = write("cmd-incident.log", `${["HEAD_MARKER", ...rows, "TAIL_MARKER"].join("\n")}\n`);
	// bash-executor 的 output 是裸尾部，pi 在 convertToLlm 时才加截断注脚
	const tail = `${rows[14]}\nTAIL_MARKER`;
	const msg = { role: "bashExecution", output: tail, truncated: true, fullOutputPath: full };
	const capped = capMessage(msg, save);
	const out = capped.output ?? "";
	expect(out.startsWith("HEAD_MARKER")).toBe(true);
	expect(out).toContain("TAIL_MARKER");
	expect(out.match(/ROW_START_\d+ /g)?.length).toBe(15);
	expect(Math.max(...out.split("\n").map((line) => line.length))).toBeLessThan(MAX_COLUMNS + 200);
	expect(out).toContain("Full output: " + full);
});

test("扩展注册 tool_result 与 context；没有改动时两个钩子都返回 undefined", () => {
	const handlers = new Map<string, (event: unknown) => unknown>();
	lineCap({ on: (event, handler) => void handlers.set(event, handler) });
	expect([...handlers.keys()].sort()).toEqual(["context", "tool_result"]);
	expect(handlers.get("tool_result")?.({ toolName: "bash", content: [{ type: "text", text: "ok" }] })).toBeUndefined();
	expect(handlers.get("context")?.({ messages: [{ role: "user", content: "hi" }] })).toBeUndefined();
});
