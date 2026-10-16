import type { ExtensionAPI, ExtensionContext } from "@oh-my-pi/pi-coding-agent";

export default function contextUsage(pi: ExtensionAPI): void {
	function update(_event: unknown, ctx: ExtensionContext): void {
		if (!ctx.hasUI) return;

		const usage = ctx.getContextUsage();
		if (!usage) {
			ctx.ui.setStatus("context-usage", undefined);
			return;
		}

		const used = `${Math.round(usage.tokens / 1000)}K`;
		const total = `${Math.round(usage.contextWindow / 1000)}K`;
		const text = ` ${used}/${total} (${usage.percent.toFixed(1)}%)`;
		const color = usage.percent >= 90 ? "error" : usage.percent >= 70 ? "warning" : "dim";
		ctx.ui.setStatus("context-usage", ctx.ui.theme.fg(color, text));
	}

	pi.on("session_start", update);
	pi.on("session_switch", update);
	pi.on("session_branch", update);
	pi.on("session_tree", update);
	pi.on("session_compact", update);
	pi.on("model_select", update);
	pi.on("agent_start", update);
	pi.on("message_end", update);
	pi.on("agent_end", update);
}
