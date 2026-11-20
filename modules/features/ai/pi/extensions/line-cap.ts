/**
 * 为什么需要：pi 内置 bash 只限总量（50KB / 2000 行）、不限单行，且只留尾部。
 * 为什么 bash 结果挂 tool_result 并回读完整输出：这个钩子运行时 pi 已经把输出截成尾部，
 * 开头只存在于 details.fullOutputPath 指向的文件里，只处理钩子拿到的文本救不回开头。
 *
 * 为什么后台结果和 !cmd 挂 context：pi-background 的完成消息是 custom 消息，用户 !cmd 是
 * bashExecution 消息，都不经过 tool_result。context 只改发给模型的副本，会话存档不变。
 */

import { createHash } from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

export const MAX_COLUMNS = 768;
export const MAX_BYTES = 50 * 1024;
export const MAX_LINES = 2000;
const HEAD_SHARE = 0.2;
const WINDOW_BYTES = 256 * 1024;
const SPILL_DIR = path.join(os.homedir(), ".pi", "agent", "line-cap");
const BASH_TOOLS = new Set(["bash", "bg_status"]);
const DELIVERY_TYPE = "background-job";
const PI_FOOTER = /\n\n\[Showing [^\]]*Full output: [^\]]*\]/;

type Block = { type: string; text?: string };
type Message = {
	role: string;
	customType?: string;
	content?: string | Block[];
	output?: string;
	truncated?: boolean;
	fullOutputPath?: string;
	excludeFromContext?: boolean;
};
type ToolResultEvent = {
	toolName: string;
	content: Block[];
	details?: { truncation?: { truncated?: boolean; totalLines?: number }; fullOutputPath?: string } | null;
	structuredContent?: unknown;
};
type ToolResultPatch = { content: Block[]; structuredContent?: unknown };

interface ExtensionAPI {
	on(event: string, handler: (event: unknown) => unknown): void;
}

export function spill(text: string): string | undefined {
	try {
		const file = path.join(SPILL_DIR, `${createHash("sha256").update(text).digest("hex").slice(0, 16)}.txt`);
		if (!fs.existsSync(file)) {
			fs.mkdirSync(SPILL_DIR, { recursive: true, mode: 0o700 });
			const tmp = `${file}.${process.pid}.tmp`;
			fs.writeFileSync(tmp, text, { mode: 0o600 });
			fs.renameSync(tmp, file);
		}
		return file;
	} catch {
		return undefined;
	}
}

export function capLine(line: string, max: number = MAX_COLUMNS): string {
	if (line.length <= max) return line;
	// 不在代理对中间截断，否则留下半个字符
	let end = max;
	const code = line.charCodeAt(end - 1);
	if (code >= 0xd800 && code <= 0xdbff) end--;
	return `${line.slice(0, end)}…[+${line.length - end} chars]`;
}

const bytes = (line: string) => Buffer.byteLength(line, "utf8") + 1;

function takeFront(lines: string[], maxBytes: number, maxLines: number): number {
	let used = 0;
	let n = 0;
	while (n < lines.length && n < maxLines && used + bytes(lines[n]) <= maxBytes) used += bytes(lines[n++]);
	return n;
}

function takeBack(lines: string[], maxBytes: number, maxLines: number): number {
	let used = 0;
	let n = 0;
	while (n < lines.length && n < maxLines && used + bytes(lines[lines.length - 1 - n]) <= maxBytes) {
		used += bytes(lines[lines.length - 1 - n++]);
	}
	return n;
}

export interface Shaped {
	text: string;
	cutLines: number;
	omittedLines: number;
}

export function shape(head: string[], tail?: string[], gap: number = 0): Shaped {
	let cutLines = 0;
	const cap = (line: string) => {
		const capped = capLine(line);
		if (capped !== line) cutLines++;
		return capped;
	};
	const h = head.map(cap);
	const t = tail?.map(cap);
	if (!t && h.length <= MAX_LINES && h.reduce((sum, line) => sum + bytes(line), 0) <= MAX_BYTES) {
		return { text: h.join("\n"), cutLines, omittedLines: 0 };
	}
	const headBytes = Math.floor(MAX_BYTES * HEAD_SHARE);
	const headLines = Math.floor(MAX_LINES * HEAD_SHARE);
	const nh = takeFront(h, headBytes, headLines);
	const back = t?.length ? t : h.slice(nh);
	const nt = takeBack(back, MAX_BYTES - headBytes, MAX_LINES - headLines);
	const between = h.length - nh - nt + (t?.length ? gap + t.length : 0);
	const after = t?.length ? 0 : gap;
	const mark = (n: number) => (n > 0 ? [`[… ${n} lines omitted …]`] : []);
	const kept = [...h.slice(0, nh), ...mark(between), ...back.slice(back.length - nt), ...mark(after)];
	return { text: kept.join("\n"), cutLines, omittedLines: between + after };
}

const splitLines = (text: string) => text.replace(/\n+$/, "").split("\n");

export function readEnds(file: string, window: number = WINDOW_BYTES): { head: string[]; tail?: string[] } {
	const size = fs.statSync(file).size;
	if (size <= window * 2) return { head: splitLines(fs.readFileSync(file, "utf8")) };
	const fd = fs.openSync(file, "r");
	try {
		const read = (position: number) => {
			const buffer = Buffer.alloc(window);
			return buffer.subarray(0, fs.readSync(fd, buffer, 0, window, position)).toString("utf8");
		};
		const head = read(0).split("\n");
		const tail = splitLines(read(size - window));
		if (head.length > 1) head.pop();
		if (tail.length > 1) tail.shift();
		else tail.length = 0;
		return { head, tail };
	} finally {
		fs.closeSync(fd);
	}
}

function capOutputText(
	text: string,
	truncated: boolean | undefined,
	fullOutputPath: string | undefined,
	totalLines: number | undefined,
	save: (t: string) => string | undefined,
): string | undefined {
	let full = truncated ? fullOutputPath : undefined;
	let shaped: Shaped | undefined;
	let suffix = "";
	if (full) {
		try {
			const ends = readEnds(full);
			const gap = ends.tail ? Math.max(0, (totalLines ?? 0) - ends.head.length - ends.tail.length) : 0;
			shaped = shape(ends.head, ends.tail, gap);
			// pi 的截断说明之后可能还有 "Command exited with code N"，必须保留
			const footer = PI_FOOTER.exec(text);
			if (footer) suffix = text.slice(footer.index + footer[0].length);
		} catch {
			full = undefined;
		}
	}
	if (!shaped) {
		shaped = shape(splitLines(text));
		if (shaped.cutLines === 0 && shaped.omittedLines === 0) return undefined;
	}
	const where = full ?? save(text) ?? "unavailable";
	return `${shaped.text}\n\n[line-cap: ${shaped.cutLines} line(s) cut to ${MAX_COLUMNS} chars, ${shaped.omittedLines} line(s) omitted. Full output: ${where}]${suffix}`;
}

export function capToolResult(event: ToolResultEvent, save: (t: string) => string | undefined = spill): ToolResultPatch | undefined {
	if (!BASH_TOOLS.has(event.toolName)) return undefined;
	const index = event.content.findIndex((block) => block.type === "text" && typeof block.text === "string");
	if (index < 0) return undefined;
	const text = event.content[index].text as string;
	const truncation = event.details?.truncation;
	const replaced = capOutputText(text, truncation?.truncated, event.details?.fullOutputPath, truncation?.totalLines, save);
	if (!replaced) return undefined;
	const content = event.content.map((block, i) => (i === index ? { ...block, text: replaced } : block));
	// 只换 content 会让 pi 丢掉 structuredContent，而 codemode 脚本读的正是它
	return { content, structuredContent: event.structuredContent };
}

export function capText(text: string, save: (t: string) => string | undefined = spill): string {
	const shaped = shape(splitLines(text));
	if (shaped.cutLines === 0 && shaped.omittedLines === 0) return text;
	const where = save(text) ?? "unavailable";
	return `${shaped.text}\n\n[line-cap: ${shaped.cutLines} line(s) cut to ${MAX_COLUMNS} chars, ${shaped.omittedLines} line(s) omitted. Full output: ${where}]`;
}

export function capMessage(m: Message, save: (t: string) => string | undefined = spill): Message {
	if (m.role === "bashExecution") {
		// 用户 !cmd 的输出由 bash-executor 截尾，和 tool_result 一样回读完整文件重排
		if (m.excludeFromContext || typeof m.output !== "string") return m;
		const replaced = capOutputText(m.output, m.truncated, m.fullOutputPath, undefined, save);
		return replaced === undefined ? m : { ...m, output: replaced };
	}
	if (m.role !== "custom" || m.customType !== DELIVERY_TYPE) return m;
	if (typeof m.content === "string") {
		const text = capText(m.content, save);
		return text === m.content ? m : { ...m, content: text };
	}
	if (!Array.isArray(m.content)) return m;
	let changed = false;
	const content = m.content.map((block) => {
		if (block.type !== "text" || typeof block.text !== "string") return block;
		const text = capText(block.text, save);
		if (text === block.text) return block;
		changed = true;
		return { ...block, text };
	});
	return changed ? { ...m, content } : m;
}

export default function lineCap(pi: ExtensionAPI) {
	pi.on("tool_result", (event) => capToolResult(event as ToolResultEvent));
	pi.on("context", (event) => {
		const { messages } = event as { messages: Message[] };
		const capped = messages.map((m) => capMessage(m));
		return capped.some((m, i) => m !== messages[i]) ? { messages: capped } : undefined;
	});
}
