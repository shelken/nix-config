/**
 * line-cap — bash 类输出进模型之前：超长单行截短，总量超限时保留头尾。
 *
 * 为什么需要：pi 内置 bash 只限总量（50KB / 2000 行）、不限单行，且只留尾部。
 * 几行几十 KB 的 JSON 会整块进上下文，开头的内容反而丢了。
 *
 * 为什么 bash 结果挂 tool_result 并回读完整输出：这个钩子运行时 pi 已经把输出截成尾部，
 * 开头只存在于 details.fullOutputPath 指向的文件里，只处理钩子拿到的文本救不回开头。
 *
 * 为什么后台结果和 !cmd 挂 context：pi-background 的完成消息是 custom 消息，用户 !cmd 是
 * bashExecution 消息，都不经过 tool_result。context 只改发给模型的副本，会话存档不变。
 *
 * 缓存：结果只由输入决定（落盘路径取原文哈希），同一条消息每次发给模型的字节相同。
 * 落盘路径若含时间戳、随机数或进程号，提供方的前缀缓存即失效。
 *
 * 不处理 read：截断源码行会让模型照残缺文本去 edit。
 */

import { createHash } from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

export const MAX_COLUMNS = 768;
// 总量与 pi 内置 bash 相同，只是从“全给尾部”改成头尾分配
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

/** 原文按内容哈希落盘，同一内容永远是同一路径；失败时返回 undefined，截断照常进行。 */
export function spill(text: string): string | undefined {
	try {
		const file = path.join(SPILL_DIR, `${createHash("sha256").update(text).digest("hex").slice(0, 16)}.txt`);
		if (!fs.existsSync(file)) {
			fs.mkdirSync(SPILL_DIR, { recursive: true, mode: 0o700 });
			// 先写临时文件再改名，进程中途退出不会留下半截文件被后续当成完整原文
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

/**
 * 先按列截短每一行，再在总量超限时保留头尾。
 * 只传 head 表示拿到了全部行；同时传 tail 表示大文件只读了两端，gap 是两端之间没读到的行数。
 */
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
	const back = t ?? h.slice(nh);
	const nt = takeBack(back, MAX_BYTES - headBytes, MAX_LINES - headLines);
	const omittedLines = h.length - nh + (t ? gap + t.length : 0) - nt;
	const kept = [...h.slice(0, nh), ...(omittedLines > 0 ? [`[… ${omittedLines} lines omitted …]`] : []), ...back.slice(back.length - nt)];
	return { text: kept.join("\n"), cutLines, omittedLines };
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
		// 窗口边缘是半截行。有多行时丢掉它；只有一行说明整个窗口落在一个超长行里：
		// 开头那段交给列截断，结尾那段没有可用信息
		if (head.length > 1) head.pop();
		if (tail.length > 1) tail.shift();
		else tail.length = 0;
		return { head, tail };
	} finally {
		fs.closeSync(fd);
	}
}

/** 返回 tool_result 的补丁；不需要改动时返回 undefined。 */
export function capToolResult(event: ToolResultEvent, save: (t: string) => string | undefined = spill): ToolResultPatch | undefined {
	if (!BASH_TOOLS.has(event.toolName)) return undefined;
	const index = event.content.findIndex((block) => block.type === "text" && typeof block.text === "string");
	if (index < 0) return undefined;
	const text = event.content[index].text as string;

	const truncation = event.details?.truncation;
	let full = truncation?.truncated ? event.details?.fullOutputPath : undefined;
	let shaped: Shaped | undefined;
	let suffix = "";
	if (full) {
		try {
			const ends = readEnds(full);
			const gap = ends.tail ? Math.max(0, (truncation?.totalLines ?? 0) - ends.head.length - ends.tail.length) : 0;
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
	const note = `[line-cap: ${shaped.cutLines} line(s) cut to ${MAX_COLUMNS} chars, ${shaped.omittedLines} line(s) omitted. Full output: ${where}]`;
	const content = event.content.map((block, i) => (i === index ? { ...block, text: `${shaped.text}\n\n${note}${suffix}` } : block));
	// 只换 content 会让 pi 丢掉 structuredContent，而 codemode 脚本读的正是它
	return { content, structuredContent: event.structuredContent };
}

export function capText(text: string, save: (t: string) => string | undefined = spill): string {
	const shaped = shape(splitLines(text));
	if (shaped.cutLines === 0 && shaped.omittedLines === 0) return text;
	const where = save(text) ?? "unavailable";
	return `${shaped.text}\n\n[line-cap: ${shaped.cutLines} line(s) cut to ${MAX_COLUMNS} chars, ${shaped.omittedLines} line(s) omitted. Full output: ${where}]`;
}

/** 返回截短后的消息；没有任何改动时返回原对象，调用方据此决定是否替换列表。 */
export function capMessage(m: Message, save: (t: string) => string | undefined = spill): Message {
	if (m.role === "bashExecution") {
		if (m.excludeFromContext || typeof m.output !== "string") return m;
		const output = capText(m.output, save);
		return output === m.output ? m : { ...m, output };
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
		// 没有改动就不返回，让 pi 保留原列表（含中途 system 消息与缓存前缀）
		return capped.some((m, i) => m !== messages[i]) ? { messages: capped } : undefined;
	});
}
