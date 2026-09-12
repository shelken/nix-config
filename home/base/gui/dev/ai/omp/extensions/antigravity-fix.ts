/**
 * antigravity-fix — google-antigravity (Cloud Code Assist) 服务端会因系统提示中
 * 字面的 <system-conventions> 标签触发过滤，返回假 429 RESOURCE_EXHAUSTED
 * (oh-my-pi#11794)。仅重命名标签为 conventions 即可通过，指令内容原样保留。
 */

const TAG = "system-conventions";

export default function antigravityFixExtension(pi: any): void {
	pi.on("before_provider_request", async (event: any, ctx: any) => {
		const model = ctx?.getModel?.();
		if (model?.provider !== "google-antigravity") return;

		const parts = event?.payload?.request?.systemInstruction?.parts;
		if (!Array.isArray(parts)) return;
		for (const part of parts) {
			if (typeof part?.text === "string" && part.text.includes(TAG)) {
				part.text = part.text.split(TAG).join("conventions");
			}
		}
	});
}
