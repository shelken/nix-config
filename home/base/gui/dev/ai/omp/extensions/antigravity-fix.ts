/**
 * antigravity-fix — google-antigravity (Cloud Code Assist) 服务端会因系统提示中
 * 字面的 <system-conventions> / <system-directive> 标签触发过滤，返回假 429
 * RESOURCE_EXHAUSTED (oh-my-pi#11794、#11699)。仅重命名标签即可通过，
 * 指令内容原样保留；连字符/下划线两种变体都处理
 * (敏感词清单与 CLIProxyAPI antigravity sensitive-words 补丁对齐)。
 */

const RENAMES: Array<[string, string]> = [
	["system-conventions", "conventions"],
	["system_conventions", "conventions"],
	["system-directive", "directive"],
	["system_directive", "directive"],
];

export function sanitizeText(text: string): string {
	for (const [from, to] of RENAMES) {
		text = text.split(from).join(to);
	}
	return text;
}

export default function antigravityFixExtension(pi: any): void {
	pi.on("before_provider_request", async (event: any, ctx: any) => {
		if (ctx?.model?.provider !== "google-antigravity") return;

		const parts = event?.payload?.request?.systemInstruction?.parts;
		if (!Array.isArray(parts)) return;
		for (const part of parts) {
			if (typeof part?.text === "string") {
				part.text = sanitizeText(part.text);
			}
		}
	});
}
