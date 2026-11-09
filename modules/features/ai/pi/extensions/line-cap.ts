/**
 * line-cap — 送进 LLM 之前，把 bash 类输出里的超长单行截短，原文落盘供按需取回。
 *
 * 为什么：pi 内置 bash 和 @pify/shell-background 都只限总量、不限单行。
 * 一行几十 KB 的 JSON/LevelDB 内容会整块进上下文（一次约 3.4 万 token）。
 * omp 的 OutputSink 在写入时按列截断（tools.outputMaxColumns，默认 768），并把完整输出存成 artifact；
 * 这里补上同一思路。计数单位是 UTF-16 码元而非 omp 的字节：中日文行放宽到约 3 倍字节，但 token 成本与字符数更接近。
 *
 * 为什么挂在 `context` 而不是 `tool_result`：shell-background 的后台完成结果
 * 是 custom 消息，不经过 tool_result；`context` 在每次调用 LLM 前运行，三条路径都覆盖，
 * 且只改发给模型的副本，会话存档和日志文件保持原样。
 *
 * 只处理 bash、shell_status、后台推送和用户 `!cmd` 的输出，不碰 read：截断源码行会让模型照残缺文本去 edit。
 *
 * 缓存：截断结果和落盘路径都只由原文决定（路径取原文哈希），同一条消息每次发给模型的字节完全相同，
 * 不破坏提供方的前缀缓存。落盘路径若改成含时间戳、随机数或每个进程不同的目录，缓存即失效。
 *
 * 落盘目录放在家目录而不是 tmpdir：Linux 的 /tmp 是多用户共享，固定路径可被他人预置软链接；
 * 家目录还让路径跨进程重启保持不变，旧消息里的路径始终有效。
 */

import { createHash } from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const MAX_COLUMNS = 768;
const SPILL_DIR = path.join(os.homedir(), ".pi", "agent", "line-cap");
const BASH_TOOLS = new Set(["bash", "shell_status"]);
const DELIVERY_TYPE = "pify-shell-background-result";

type Block = { type: string; text?: string };
type Message = {
	role: string;
	toolName?: string;
	customType?: string;
	content?: string | Block[];
	/** bashExecution（用户 !cmd）的输出在 output，不在 content */
	output?: string;
	excludeFromContext?: boolean;
};

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

export function capText(text: string, max: number = MAX_COLUMNS, save: (t: string) => string | undefined = spill): string {
	if (text.length <= max) return text;
	let cut = 0;
	const lines = text.split("\n").map((line, i) => {
		if (line.length <= max) return line;
		cut++;
		// 不在代理对中间截断，否则留下半个字符
		let end = max;
		const code = line.charCodeAt(end - 1);
		if (code >= 0xd800 && code <= 0xdbff) end--;
		return `${line.slice(0, end)}…[line ${i + 1}, +${line.length - end} chars]`;
	});
	if (cut === 0) return text;
	const file = save(text);
	const where = file ? `; full text: ${file} (one line: sed -n 'Np' ${file} | cut -c1-4000)` : "";
	return `${lines.join("\n")}\n[line-cap: ${cut} line(s) cut to ${max} chars${where}]`;
}

function isCapped(m: Message): boolean {
	if (m.role === "toolResult") return BASH_TOOLS.has(m.toolName ?? "");
	if (m.role === "bashExecution") return !m.excludeFromContext;
	return m.role === "custom" && m.customType === DELIVERY_TYPE;
}

/** 返回截短后的消息；没有任何改动时返回原对象，调用方据此决定是否替换列表。 */
export function capMessage(m: Message): Message {
	if (!isCapped(m)) return m;
	if (m.role === "bashExecution") {
		if (typeof m.output !== "string") return m;
		const output = capText(m.output);
		return output === m.output ? m : { ...m, output };
	}
	if (typeof m.content === "string") {
		const text = capText(m.content);
		return text === m.content ? m : { ...m, content: text };
	}
	if (!Array.isArray(m.content)) return m;
	let changed = false;
	const content = m.content.map((block) => {
		if (block.type !== "text" || typeof block.text !== "string") return block;
		const text = capText(block.text);
		if (text === block.text) return block;
		changed = true;
		return { ...block, text };
	});
	return changed ? { ...m, content } : m;
}

export default function lineCap(pi: ExtensionAPI) {
	pi.on("context", (event) => {
		const { messages } = event as { messages: Message[] };
		const capped = messages.map(capMessage);
		// 没有改动就不返回，让 pi 保留原列表（含中途 system 消息与缓存前缀）
		return capped.some((m, i) => m !== messages[i]) ? { messages: capped } : undefined;
	});
}
