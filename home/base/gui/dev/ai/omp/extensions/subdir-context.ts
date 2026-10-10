/**
 * subdir-context — 读取子目录文件时，自动注入该文件路径链上的 AGENTS.md 上下文。
 *
 * 移植自 npm:pi-subdir-context v1.1.7（MIT, Anton Kuzmenko），作为 omp 对
 * 「cwd 之下子目录 AGENTS.md 只提示指针、不自动注入」行为的补强；宿主已加载
 * 的 cwd 层文件与上游一样跳过。整个会话内每个文件只注入一次。
 */

import fs from "node:fs";
import os from "node:os";
import path from "node:path";

type TextBlock = { type: "text"; text: string };

interface ExtensionCtx {
	cwd: string;
	hasUI?: boolean;
	ui?: {
		notify?: (message: string, type?: "info" | "warning" | "error") => void;
	};
}

type ToolResultEvent = {
	toolName: string;
	isError?: boolean;
	input?: Record<string, unknown>;
	content?: unknown[];
	details?: unknown;
};

type ToolResultPatch = { content?: unknown[]; details?: unknown };

interface ExtensionAPI {
	on(event: string, handler: (event: unknown, ctx: ExtensionCtx) => unknown): void;
	[key: string]: unknown;
}

// AGENTS.override.md 视为同目录下的 AGENTS.md，同目录同时存在时优先生效
const AGENTS_FILENAMES = ["AGENTS.override.md", "AGENTS.md", "CLAUDE.md"];

export default function subdirContext(pi: ExtensionAPI): void {
	const loadedAgents = new Set<string>();
	let currentCwd = "";
	let sessionCwd = "";
	let homeDir = "";

	function resolvePath(targetPath: string, baseDir: string): string {
		// omp read 会展开 ~ 前缀，这里保持同语义，否则 home 兜底对 ~/x 写法失效
		const expanded =
			targetPath === "~"
				? os.homedir()
				: targetPath.startsWith("~/")
					? path.join(os.homedir(), targetPath.slice(2))
					: targetPath;
		const absolute = path.isAbsolute(expanded)
			? path.normalize(expanded)
			: path.resolve(baseDir, expanded);
		try {
			return fs.realpathSync(absolute);
		} catch {
			// 选择器/容器路径（big.ts:120-200、archive.zip:entry）没有真实文件可解析，
			// 原样返回，由调用方按字符串路径继续做目录链分析
			return absolute;
		}
	}

	function isInsideRoot(rootDir: string, targetPath: string): boolean {
		if (!rootDir) return false;
		const relative = path.relative(rootDir, targetPath);
		return relative === "" || (!relative.startsWith("..") && !path.isAbsolute(relative));
	}

	// 用户级 native agent 目录（PI_CODING_AGENT_DIR 可重定位），其中的 AGENTS.md 宿主已注入
	const agentDirs = [
		process.env.PI_CODING_AGENT_DIR,
		process.env.OMP_CODING_AGENT_DIR,
		process.env.OMP_AGENT_DIR,
		path.join(os.homedir(), ".pi", "agent"),
		path.join(os.homedir(), ".omp", "agent"),
	]
		.filter((d): d is string => Boolean(d))
		.map((d) => resolvePath(d, process.cwd()));

	function getAgentsFileFromDir(dir: string): string {
		for (const filename of AGENTS_FILENAMES) {
			const candidate = path.join(dir, filename);
			if (fs.existsSync(candidate)) return candidate;
		}
		return "";
	}

	function resetSession(cwd: string): void {
		sessionCwd = cwd;
		currentCwd = resolvePath(cwd, process.cwd());
		homeDir = resolvePath(os.homedir(), process.cwd());
		loadedAgents.clear();
	}

	function findAgentsFiles(filePath: string, rootDir: string): string[] {
		if (!rootDir) return [];

		const agentsFiles: string[] = [];
		let dir = path.dirname(filePath);

		while (isInsideRoot(rootDir, dir)) {
			const candidate = getAgentsFileFromDir(dir);
			// 宿主启动时已注入的不再重复：cwd 及其祖先链上的文件（omp 从 cwd 读到仓库根），
			// 以及用户级 native agent 目录下的 AGENTS.md
			// 已知缺口：<cwd>/.claude/CLAUDE.md、<cwd>/.gemini/GEMINI.md 等「仅 cwd 配置目录」
			// 的上下文文件同样由宿主加载，读这些目录下的文件时仍会重复注入一次
			const hostLoaded = isInsideRoot(dir, currentCwd) || agentDirs.some((d) => isInsideRoot(d, candidate));
			if (candidate && !hostLoaded) agentsFiles.push(candidate);

			if (dir === rootDir) break;

			const parent = path.dirname(dir);
			if (parent === dir) break;
			dir = parent;
		}

		// 距离根目录近的排前面，最贴近读取文件的最靠后、权重最高
		return agentsFiles.reverse();
	}

	const handleSessionChange = (_event: unknown, ctx: ExtensionCtx): void => {
		resetSession(ctx.cwd);
	};

	pi.on("session_start", handleSessionChange);
	// omp 独有：切换/分支/树导航会恢复另一条对话分支，旧分支里注入过的
	// 上下文在新分支中并不存在，必须重置去重集，否则恢复后上下文缺失
	pi.on("session_switch", handleSessionChange);
	pi.on("session_branch", handleSessionChange);
	pi.on("session_tree", handleSessionChange);

	pi.on("tool_result", async (event, ctx): Promise<ToolResultPatch | undefined> => {
		const result = event as ToolResultEvent;
		if (result.toolName !== "read" || result.isError) return undefined;

		const pathInput = result.input?.path;
		if (typeof pathInput !== "string" || pathInput === "") return undefined;

		// /move、/wt 会在同一会话内就地改 cwd 且不触发会话事件，必须每次比对
		if (sessionCwd !== ctx.cwd) resetSession(ctx.cwd);

		// 剥离行选择器（:50-100、:raw 等）后再做目录链分析；容器/选择器读取
		// （archive.zip:entry、big.ts:120-200）与上游一致仍能注入所在目录的上下文
		const rawPath = resolvePath(pathInput, currentCwd);
		const rawBase = path.basename(rawPath);
		const cleanBase = rawBase.replace(/(?::(?:\d[\d+\-,]*|raw|img|conflicts))+$/i, "");
		const absolutePath = cleanBase === rawBase ? rawPath : path.join(path.dirname(rawPath), cleanBase);

		if (AGENTS_FILENAMES.includes(path.basename(absolutePath))) {
			loadedAgents.add(path.normalize(absolutePath));
			return undefined;
		}

		const searchRoot = isInsideRoot(currentCwd, absolutePath)
			? currentCwd
			: isInsideRoot(homeDir, absolutePath)
				? homeDir
				: "";
		if (!searchRoot) return undefined;

		const additions: TextBlock[] = [];

		for (const agentsPath of findAgentsFiles(absolutePath, searchRoot)) {
			const normalizedAgentsPath = path.normalize(agentsPath);
			if (loadedAgents.has(normalizedAgentsPath)) continue;

			// 先占位再读：并发 tool_result 在 await 处交错，读后再占位会重复注入；
			// 读取失败时回滚占位，保留下次重读的机会
			loadedAgents.add(normalizedAgentsPath);
			try {
				const content = await fs.promises.readFile(agentsPath, "utf-8");
				additions.push({
					type: "text",
					text: `Loaded subdirectory context from ${agentsPath}\n\n${content}`,
				});
			} catch (error) {
				loadedAgents.delete(normalizedAgentsPath);
				if (ctx.hasUI) ctx.ui?.notify?.(`Failed to load ${agentsPath}: ${String(error)}`, "warning");
			}
		}

		if (!additions.length) return undefined;

		const baseContent = Array.isArray(result.content) ? result.content : [];
		return { content: [...baseContent, ...additions], details: result.details };
	});
}
