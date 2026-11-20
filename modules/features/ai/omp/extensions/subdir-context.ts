/**
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

const AGENTS_FILENAMES = ["AGENTS.override.md", "AGENTS.md", "CLAUDE.md"];

const PATH_TOOLS = new Set(["read", "grep", "find", "ls", "glob", "ffgrep", "fffind"]);
const GLOB_CHARS = /[*?[{]/;
const SELECTOR_SUFFIX = /(?::(?:\d[\d+\-,]*|raw|img|conflicts))+$/i;

function globStaticPrefix(entry: string): string {
	const segments = entry.split("/");
	const index = segments.findIndex((s) => GLOB_CHARS.test(s));
	if (index < 0) return entry;
	return segments.slice(0, index).join("/");
}

function isDirectory(target: string): boolean {
	try {
		return fs.statSync(target).isDirectory();
	} catch {
		return false;
	}
}

export default function subdirContext(pi: ExtensionAPI): void {
	const loadedAgents = new Set<string>();
	let currentCwd = "";
	let sessionCwd = "";
	let homeDir = "";

	function resolvePath(targetPath: string, baseDir: string): string {
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
			return absolute;
		}
	}

	function isInsideRoot(rootDir: string, targetPath: string): boolean {
		if (!rootDir) return false;
		const relative = path.relative(rootDir, targetPath);
		return relative === "" || (!relative.startsWith("..") && !path.isAbsolute(relative));
	}

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

	function findAgentsFiles(startDir: string, rootDir: string): string[] {
		if (!rootDir) return [];

		const agentsFiles: string[] = [];
		let dir = startDir;

		while (isInsideRoot(rootDir, dir)) {
			const candidate = getAgentsFileFromDir(dir);
			const hostLoaded = isInsideRoot(dir, currentCwd) || agentDirs.some((d) => isInsideRoot(d, candidate));
			if (candidate && !hostLoaded) agentsFiles.push(candidate);

			if (dir === rootDir) break;

			const parent = path.dirname(dir);
			if (parent === dir) break;
			dir = parent;
		}

		return agentsFiles.reverse();
	}

	const handleSessionChange = (_event: unknown, ctx: ExtensionCtx): void => {
		resetSession(ctx.cwd);
	};

	pi.on("session_start", handleSessionChange);
	pi.on("session_switch", handleSessionChange);
	pi.on("session_branch", handleSessionChange);
	pi.on("session_tree", handleSessionChange);

	pi.on("tool_result", async (event, ctx): Promise<ToolResultPatch | undefined> => {
		const result = event as ToolResultEvent;
		if (!PATH_TOOLS.has(result.toolName) || result.isError) return undefined;

		const pathInput = result.input?.path;
		if (typeof pathInput !== "string" || pathInput === "") return undefined;

		if (sessionCwd !== ctx.cwd) resetSession(ctx.cwd);

		const isRead = result.toolName === "read";
		const entries =
			isRead || fs.existsSync(resolvePath(pathInput, currentCwd))
				? [pathInput]
				: pathInput.split(/[,;\s]+/).filter(Boolean);

		const additions: TextBlock[] = [];

		for (const entry of entries) {
			const rawPath = resolvePath(isRead ? entry : globStaticPrefix(entry), currentCwd);
			const rawBase = path.basename(rawPath);
			const cleanBase = rawBase.replace(SELECTOR_SUFFIX, "");
			const absolutePath = cleanBase === rawBase ? rawPath : path.join(path.dirname(rawPath), cleanBase);

			if (isRead && AGENTS_FILENAMES.includes(path.basename(absolutePath))) {
				loadedAgents.add(path.normalize(absolutePath));
				continue;
			}

			const searchRoot = isInsideRoot(currentCwd, absolutePath)
				? currentCwd
				: isInsideRoot(homeDir, absolutePath)
					? homeDir
					: "";
			if (!searchRoot) continue;

			const startDir = isDirectory(absolutePath) ? absolutePath : path.dirname(absolutePath);

			for (const agentsPath of findAgentsFiles(startDir, searchRoot)) {
				const normalizedAgentsPath = path.normalize(agentsPath);
				if (loadedAgents.has(normalizedAgentsPath)) continue;

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
		}

		if (!additions.length) return undefined;

		const baseContent = Array.isArray(result.content) ? result.content : [];
		return { content: [...baseContent, ...additions], details: result.details };
	});
}
