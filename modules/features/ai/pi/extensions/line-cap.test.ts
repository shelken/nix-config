/**
 * line-cap 扩展测试：纯函数 + 临时目录，不触碰真实会话，也不写 ~/.pi/agent/line-cap。
 * 覆盖：列截断、头尾保留、回读完整输出、失败状态保留、文件丢失回退、后台消息与 !cmd、缓存稳定。
 */

import { afterAll, expect, test } from "bun:test";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import lineCap, { capLine, capMessage, capToolResult, MAX_BYTES, MAX_COLUMNS, readEnds, shape } from "./line-cap.ts";

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "line-cap-test-"));
afterAll(() => fs.rmSync(tmp, { recursive: true, force: true }));

const save = () => "/spill/x.txt";
const write = (name: string, text: string) => {
	const file = path.join(tmp, name);
	fs.writeFileSync(file, text);
	return file;
};
const text = (patch: { content: { text?: string }[] } | undefined) => patch?.content[0].text ?? "";

test("capLine：不超长原样返回，超长截短并标出省略字符数，不切开代理对", () => {
	expect(capLine("short")).toBe("short");
	expect(capLine("a".repeat(1000))).toBe(`${"a".repeat(MAX_COLUMNS)}…[+232 chars]`);
	expect(capLine(`${"a".repeat(MAX_COLUMNS - 1)}😀x`)).toBe(`${"a".repeat(MAX_COLUMNS - 1)}…[+3 chars]`);
});

test("shape：总量超限时保留开头和结尾，中间用一行标记说明省略了多少行", () => {
	const lines = Array.from({ length: 3000 }, (_, i) => `L${i} ${"y".repeat(74)}`);
	const shaped = shape(lines);
	const out = shaped.text.split("\n");
	expect(out[0]).toBe(lines[0]);
	expect(out.at(-1)).toBe(lines.at(-1));
	expect(out).toContain(`[… ${shaped.omittedLines} lines omitted …]`);
	expect(shaped.omittedLines + out.length - 1).toBe(3000);
	expect(Buffer.byteLength(shaped.text)).toBeLessThanOrEqual(MAX_BYTES + 100);
});

test("shape：没超限的输出一字不改", () => {
	expect(shape(["a", "b"])).toEqual({ text: "a\nb", cutLines: 0, omittedLines: 0 });
});

test("readEnds：大文件只读两端并丢掉边缘的半截行；单个超长行只留开头", () => {
	const lines = Array.from({ length: 20000 }, (_, i) => `L${i} ${"y".repeat(74)}`);
	const ends = readEnds(write("big.log", `${lines.join("\n")}\n`));
	expect(ends.head[0]).toBe(lines[0]);
	expect(ends.head.every((line, i) => line === lines[i])).toBe(true);
	expect(ends.tail?.at(-1)).toBe(lines.at(-1));
	expect(ends.tail?.every((line, i, all) => line === lines[20000 - all.length + i])).toBe(true);

	const giant = readEnds(write("giant.log", `START${"z".repeat(2_000_000)}END\n`));
	expect(giant.head.length).toBe(1);
	expect(giant.tail).toEqual([]);
	expect(shape(giant.head, giant.tail).text.startsWith("START")).toBe(true);
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

test("shape：尾部窗口只剩一行超长行被清空时，回退用头部余量填充 80% 预算，不浪费", () => {
	const lines = Array.from({ length: 3000 }, (_, i) => `L${i} ${"y".repeat(94)}`);
	const giant = "GIANT " + "z".repeat(300 * 1024);
	const full = write("tail-giant.log", `${[...lines, giant].join("\n")}\n`);
	const ends = readEnds(full);
	expect(ends.tail).toEqual([]);
	const shaped = shape(ends.head, ends.tail);
	const out = shaped.text.split("\n");
	// 回退后开头仍在、输出行数远多于不回退时的 104 行、字节接近 50KB 上限
	expect(out[0]).toBe(lines[0]);
	expect(out.length).toBeGreaterThan(400);
	expect(Buffer.byteLength(shaped.text)).toBeGreaterThan(40 * 1024);
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
