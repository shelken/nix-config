/* EXTERNAL: pi-fff@0.11.0 在 override 模式下加载时会先向工具表注册无 defaultActive: false 的
 * ffgrep/fffind/fff-multi-grep 占位工具；pi 的 _restoreToolsFromTranscript() 在 /tree 后会把
 * 分支历史未提及的默认激活扩展工具重新激活，导致系统提示词变化与缓存失效。等上游
 * dmtrKovalenko/fff 修复后删除本扩展。
 */

const OVERRIDE_PAIRS: readonly (readonly [overrideName: string, fffName: string])[] = [
	["grep", "ffgrep"],
	["find", "fffind"],
	["multi_grep", "fff-multi-grep"],
];

interface ToolInfo {
	name: string;
	description?: string;
}

interface ExtensionAPI {
	on(event: string, handler: () => void): void;
	getActiveTools(): string[];
	getAllTools(): ToolInfo[];
	setActiveTools(toolNames: string[]): void;
}

export function pruneResurrectedFffTools(pi: Pick<ExtensionAPI, "getActiveTools" | "getAllTools" | "setActiveTools">): boolean {
	const active = pi.getActiveTools();
	const activeSet = new Set(active);
	const descriptions = new Map(pi.getAllTools().map((tool) => [tool.name, tool.description]));

	const stale = new Set<string>();
	for (const [overrideName, fffName] of OVERRIDE_PAIRS) {
		if (!activeSet.has(overrideName) || !activeSet.has(fffName)) continue;
		const overrideDesc = descriptions.get(overrideName);
		if (overrideDesc && overrideDesc === descriptions.get(fffName)) stale.add(fffName);
	}

	if (stale.size === 0) return false;
	pi.setActiveTools(active.filter((name) => !stale.has(name)));
	return true;
}

export default function fffOverrideGuard(pi: ExtensionAPI) {
	const prune = () => {
		pruneResurrectedFffTools(pi);
	};
	pi.on("session_tree", prune);
	pi.on("session_start", prune);
}
