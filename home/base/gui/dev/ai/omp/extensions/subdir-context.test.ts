/**
 * subdir-context 扩展测试：纯内存 + 临时目录，不触碰真实会话。
 * 覆盖：注入链顺序、session 内去重、并发读取去重（上游 bug）、
 * 分支重置（omp 补强）、cwd 层排除、override 优先、直接读取、越界与 URI 拒绝。
 */

import { expect, test } from "bun:test";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import subdirContextExtension from "./subdir-context.ts";

type Handler = (event: unknown, ctx: ExtensionCtx) => unknown;
type ExtensionCtx = { cwd: string; hasUI: boolean };

interface ExtensionUnderTest {
	on(event: string, handler: Handler): void;
}

type ToolResultEvent = {
	toolName: string;
	isError: boolean;
	input: { path: string };
	content: unknown[];
	details: unknown;
};

type ToolResultPatch = { content?: unknown[]; details?: unknown };

function isTextBlock(block: unknown): block is { type: "text"; text: string } {
	return typeof block === "object" && block !== null && "type" in block && block.type === "text";
}

function isToolResultPatch(value: unknown): value is ToolResultPatch {
	return typeof value === "object" && value !== null && ("content" in value || "details" in value);
}

function loadExtension(): Map<string, Handler[]> {
	const handlers = new Map<string, Handler[]>();
	const pi: ExtensionUnderTest = {
		on(event, handler) {
			const list = handlers.get(event) ?? [];
			list.push(handler);
			handlers.set(event, list);
		},
	};
	subdirContextExtension(pi);
	return handlers;
}

const SESSION_EVENTS = ["session_start", "session_switch", "session_branch", "session_tree"];

function fireSession(handlers: Map<string, Handler[]>, cwd: string): void {
	for (const name of SESSION_EVENTS) {
		for (const handler of handlers.get(name) ?? []) handler({}, { cwd, hasUI: false });
	}
}

async function runRead(
	handlers: Map<string, Handler[]>,
	inputPath: string,
	cwd: string,
): Promise<ToolResultPatch | undefined> {
	const event: ToolResultEvent = {
		toolName: "read",
		isError: false,
		input: { path: inputPath },
		content: [{ type: "text", text: "file body" }],
		details: { bytes: 9 },
	};
	let result: unknown;
	for (const handler of handlers.get("tool_result") ?? []) {
		result = await handler(event, { cwd, hasUI: false });
	}
	return isToolResultPatch(result) ? result : undefined;
}

function injectedTexts(result: ToolResultPatch | undefined): string[] {
	const texts: string[] = [];
	for (const block of result?.content?.slice(1) ?? []) {
		if (isTextBlock(block)) texts.push(block.text);
	}
	return texts;
}

function makeProject(): string {
	const root = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), "subdir-ctx-")));
	fs.mkdirSync(path.join(root, "src/components"), { recursive: true });
	fs.writeFileSync(path.join(root, "AGENTS.md"), "ROOT-CONTEXT");
	fs.writeFileSync(path.join(root, "src", "AGENTS.md"), "SRC-CONTEXT");
	fs.writeFileSync(path.join(root, "src", "a.ts"), "a");
	fs.writeFileSync(path.join(root, "src", "b.ts"), "b");
	fs.writeFileSync(path.join(root, "src", "AGENTS.override.md"), "SRC-OVERRIDE");
	fs.writeFileSync(path.join(root, "src", "components", "AGENTS.md"), "COMPONENT-CONTEXT");
	fs.writeFileSync(path.join(root, "src", "components", "Button.tsx"), "export {}");
	return root;
}

test("读取子目录文件注入路径链上的上下文，根优先、近文件最后", async () => {
	const root = makeProject();
	const handlers = loadExtension();
	fireSession(handlers, root);

	const result = await runRead(handlers, path.join(root, "src/components/Button.tsx"), root);
	const texts = injectedTexts(result);

	expect(texts).toHaveLength(2);
	expect(texts[0]).toContain(path.join(root, "src", "AGENTS.override.md"));
	expect(texts[0]).toContain("SRC-OVERRIDE");
	expect(texts[1]).toContain(path.join(root, "src", "components", "AGENTS.md"));
	expect(texts[1]).toContain("COMPONENT-CONTEXT");
	expect(result?.details).toEqual({ bytes: 9 });
	fs.rmSync(root, { recursive: true, force: true });
});

test("同 session 内第二次读取不再注入", async () => {
	const root = makeProject();
	const handlers = loadExtension();
	fireSession(handlers, root);

	await runRead(handlers, path.join(root, "src/a.ts"), root);
	const second = await runRead(handlers, path.join(root, "src/b.ts"), root);

	expect(injectedTexts(second)).toHaveLength(0);
	fs.rmSync(root, { recursive: true, force: true });
});

test("并发读取同一子目录只注入一次（上游重复注入 bug 回归）", async () => {
	const root = makeProject();
	const handlers = loadExtension();
	fireSession(handlers, root);

	const [first, second] = await Promise.all([
		runRead(handlers, path.join(root, "src/a.ts"), root),
		runRead(handlers, path.join(root, "src/b.ts"), root),
	]);

	const total = injectedTexts(first).length + injectedTexts(second).length;
	expect(total).toBe(1);
	fs.rmSync(root, { recursive: true, force: true });
});

test("session_branch / session_switch / session_tree 各自重置去重集（omp 补强）", async () => {
	for (const eventName of ["session_branch", "session_switch", "session_tree"]) {
		const root = makeProject();
		const handlers = loadExtension();
		fireSession(handlers, root);

		await runRead(handlers, path.join(root, "src/a.ts"), root);
		for (const handler of handlers.get(eventName) ?? []) handler({}, { cwd: root, hasUI: false });

		const afterBranch = await runRead(handlers, path.join(root, "src/b.ts"), root);
		const branchTexts = injectedTexts(afterBranch);
		expect(branchTexts).toHaveLength(1);
		expect(branchTexts[0]).toContain("SRC-OVERRIDE");
		fs.rmSync(root, { recursive: true, force: true });
	}
});

test("cwd 层自身的 AGENTS.md 不注入（宿主已加载）", async () => {
	const root = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), "subdir-ctx-")));
	fs.writeFileSync(path.join(root, "AGENTS.md"), "ROOT-ONLY");
	fs.writeFileSync(path.join(root, "top.ts"), "t");
	const handlers = loadExtension();
	fireSession(handlers, root);

	const result = await runRead(handlers, path.join(root, "top.ts"), root);
	expect(result).toBeUndefined();
	fs.rmSync(root, { recursive: true, force: true });
});

test("直接读取子目录 AGENTS.md 只标记不重复注入", async () => {
	const root = makeProject();
	const handlers = loadExtension();
	fireSession(handlers, root);

	const direct = await runRead(handlers, path.join(root, "src/AGENTS.override.md"), root);
	expect(injectedTexts(direct)).toHaveLength(0);

	const later = await runRead(handlers, path.join(root, "src/a.ts"), root);
	expect(injectedTexts(later)).toHaveLength(0);
	fs.rmSync(root, { recursive: true, force: true });
});

test("cwd 与 home 之外的路径与内部 URI 不注入", async () => {
	const root = makeProject();
	const handlers = loadExtension();
	fireSession(handlers, root);

	// /etc/hosts 真实存在但在 cwd 与 home 之外，真正走到 searchRoot 为空的分支
	const outside = await runRead(handlers, "/etc/hosts", root);
	expect(outside).toBeUndefined();

	const uri = await runRead(handlers, "skill://pi-extension-best-practice", root);
	expect(uri).toBeUndefined();
	fs.rmSync(root, { recursive: true, force: true });
});

test("带行选择器/容器语法的读取仍注入所在目录链", async () => {
	const root = makeProject();
	const handlers = loadExtension();
	fireSession(handlers, root);

	const rawMode = await runRead(handlers, `${path.join(root, "src/a.ts")}:raw`, root);
	const rawTexts = injectedTexts(rawMode);
	expect(rawTexts).toHaveLength(1);
	expect(rawTexts[0]).toContain("SRC-OVERRIDE");

	const ranged = await runRead(handlers, `${path.join(root, "src/components/Button.tsx")}:5-16`, root);
	const rangedTexts = injectedTexts(ranged);
	expect(rangedTexts).toHaveLength(1);
	expect(rangedTexts[0]).toContain("COMPONENT-CONTEXT");

	// 直接读取带选择器的 AGENTS 文件：剥离选择器后识别为 agents 文件，不重复注入
	const direct = await runRead(handlers, `${path.join(root, "src/AGENTS.md")}:10-20`, root);
	expect(injectedTexts(direct)).toHaveLength(0);
	fs.rmSync(root, { recursive: true, force: true });
});

test("会话内 cwd 就地变更（/move 类）后按新 cwd 解析相对路径", async () => {
	const rootA = makeProject();
	const rootB = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), "subdir-ctx-moved-")));
	fs.mkdirSync(path.join(rootB, "pkg"), { recursive: true });
	fs.writeFileSync(path.join(rootB, "pkg", "AGENTS.md"), "MOVED-CONTEXT");
	fs.writeFileSync(path.join(rootB, "pkg", "f.txt"), "f");
	const handlers = loadExtension();
	fireSession(handlers, rootA);

	await runRead(handlers, path.join(rootA, "src/a.ts"), rootA);
	const afterMove = await runRead(handlers, "pkg/f.txt", rootB);
	const texts = injectedTexts(afterMove);
	expect(texts).toHaveLength(1);
	expect(texts[0]).toContain("MOVED-CONTEXT");
	fs.rmSync(rootA, { recursive: true, force: true });
	fs.rmSync(rootB, { recursive: true, force: true });
});

test("AGENTS 文件读取失败时回滚占位并可重试", async () => {
	const root = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), "subdir-ctx-")));
	// 用同名目录冒充 AGENTS.md 制造读取失败（EISDIR）
	fs.mkdirSync(path.join(root, "pkg/AGENTS.md"), { recursive: true });
	fs.writeFileSync(path.join(root, "pkg/f.txt"), "f");
	const handlers = loadExtension();
	fireSession(handlers, root);

	const failed = await runRead(handlers, path.join(root, "pkg/f.txt"), root);
	expect(injectedTexts(failed)).toHaveLength(0);

	fs.rmdirSync(path.join(root, "pkg/AGENTS.md"));
	fs.writeFileSync(path.join(root, "pkg/AGENTS.md"), "RETRY-CONTEXT");
	const retried = await runRead(handlers, path.join(root, "pkg/f.txt"), root);
	expect(injectedTexts(retried)).toHaveLength(1);
	fs.rmSync(root, { recursive: true, force: true });
});

test("home 目录下其他项目读取时注入其上下文，且 session 内去重", async () => {
	const home = os.homedir();
	const proj = fs.realpathSync(fs.mkdtempSync(path.join(home, ".subdir-ctx-selftest-")));
	fs.mkdirSync(path.join(proj, "lib"), { recursive: true });
	fs.writeFileSync(path.join(proj, "AGENTS.md"), "HOMEPROJECT-CONTEXT");
	fs.writeFileSync(path.join(proj, "lib", "m.ts"), "m");
	// 会话 cwd 在 tmpdir（home 之外），proj 是外部项目，其根 AGENTS.md 不属于宿主已加载范围
	const sessionCwd = fs.realpathSync(os.tmpdir());
	const handlers = loadExtension();
	fireSession(handlers, sessionCwd);

	try {
		// 用 ~/ 前缀写法覆盖 home 展开（omp read 同语义）
		const tildePath = `~/${path.relative(home, path.join(proj, "lib/m.ts"))}`;
		const first = await runRead(handlers, tildePath, sessionCwd);
		expect(injectedTexts(first).some((t) => t.includes("HOMEPROJECT-CONTEXT"))).toBe(true);

		const second = await runRead(handlers, path.join(proj, "lib/m.ts"), sessionCwd);
		expect(injectedTexts(second)).toHaveLength(0);
	} finally {
		fs.rmSync(proj, { recursive: true, force: true });
	}
});

test("宿主已加载的 cwd 祖先链与用户级 agent 文件不重复注入", async () => {
	const home = os.homedir();
	const proj = fs.realpathSync(fs.mkdtempSync(path.join(home, ".subdir-ctx-selftest-")));
	const prevAgentDir = process.env.PI_CODING_AGENT_DIR;
	try {
		// 用户级 native agent 目录重定位到 proj/.agentdir
		process.env.PI_CODING_AGENT_DIR = path.join(proj, ".agentdir");
		fs.mkdirSync(path.join(proj, ".agentdir/sub"), { recursive: true });
		fs.writeFileSync(path.join(proj, ".agentdir/AGENTS.md"), "USERLEVEL-CONTEXT");
		fs.writeFileSync(path.join(proj, ".agentdir/sub/f.ts"), "f");
		fs.writeFileSync(path.join(proj, "AGENTS.md"), "PROJ-ROOT-CONTEXT");
		fs.mkdirSync(path.join(proj, "inner"), { recursive: true });
		fs.mkdirSync(path.join(proj, "other"), { recursive: true });
		fs.writeFileSync(path.join(proj, "other/x.ts"), "x");

		const handlers = loadExtension();
		const sessionCwd = path.join(proj, "inner");
		fireSession(handlers, sessionCwd);

		// proj/AGENTS.md 是 cwd 的祖先、.agentdir/AGENTS.md 是用户级，两者宿主启动时已注入
		const sibling = await runRead(handlers, path.join(proj, "other/x.ts"), sessionCwd);
		const texts = injectedTexts(sibling);
		expect(texts.some((t) => t.includes("PROJ-ROOT-CONTEXT"))).toBe(false);
		expect(texts.some((t) => t.includes("USERLEVEL-CONTEXT"))).toBe(false);

		const agentRead = await runRead(handlers, path.join(proj, ".agentdir/sub/f.ts"), sessionCwd);
		expect(injectedTexts(agentRead).some((t) => t.includes("USERLEVEL-CONTEXT"))).toBe(false);

		// 防护不能误伤：不在 cwd 祖先链上的子目录上下文仍要注入
		fs.writeFileSync(path.join(proj, "other/AGENTS.md"), "OTHER-CONTEXT");
		fs.writeFileSync(path.join(proj, "other/y.ts"), "y");
		const nested = await runRead(handlers, path.join(proj, "other/y.ts"), sessionCwd);
		expect(injectedTexts(nested).some((t) => t.includes("OTHER-CONTEXT"))).toBe(true);
	} finally {
		if (prevAgentDir === undefined) delete process.env.PI_CODING_AGENT_DIR;
		else process.env.PI_CODING_AGENT_DIR = prevAgentDir;
		fs.rmSync(proj, { recursive: true, force: true });
	}
});
