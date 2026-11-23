import { expect, test } from "bun:test";

import fffOverrideGuard, { pruneResurrectedFffTools } from "./fff-override-guard.ts";

function makeFakePi(active: string[], all: { name: string; description?: string }[]) {
	let current = [...active];
	let setCalls = 0;
	const handlers = new Map<string, () => void>();
	return {
		api: {
			on(event: string, handler: () => void) {
				handlers.set(event, handler);
			},
			getActiveTools: () => [...current],
			getAllTools: () => all,
			setActiveTools(names: string[]) {
				current = [...names];
				setCalls++;
			},
		},
		get active() {
			return current;
		},
		get setCalls() {
			return setCalls;
		},
		emit(event: string) {
			handlers.get(event)?.();
		},
	};
}

test("override 模式下 /tree 误复活 ffgrep/fffind 时自动剔除，保持原有工具顺序", () => {
	const fake = makeFakePi(
		["read", "grep", "find", "ffgrep", "fffind"],
		[
			{ name: "read", description: "Read file" },
			{ name: "grep", description: "Grep file contents. Smart-case." },
			{ name: "ffgrep", description: "Grep file contents. Smart-case." },
			{ name: "find", description: "Fuzzy path search." },
			{ name: "fffind", description: "Fuzzy path search." },
		],
	);

	fffOverrideGuard(fake.api);
	fake.emit("session_tree");

	expect(fake.active).toEqual(["read", "grep", "find"]);
	expect(fake.setCalls).toBe(1);
});

test("非 override 模式或 $HOME 降级（grep 与 ffgrep 描述不同）时不误删", () => {
	const fake = makeFakePi(
		["read", "grep", "find", "ffgrep", "fffind"],
		[
			{ name: "read", description: "Read file" },
			{ name: "grep", description: "Built-in grep" },
			{ name: "ffgrep", description: "Grep file contents. Smart-case." },
			{ name: "find", description: "Built-in find" },
			{ name: "fffind", description: "Fuzzy path search." },
		],
	);

	expect(pruneResurrectedFffTools(fake.api)).toBe(false);
	expect(fake.active).toEqual(["read", "grep", "find", "ffgrep", "fffind"]);
	expect(fake.setCalls).toBe(0);
});

test("没有误复活时不触发 setActiveTools", () => {
	const fake = makeFakePi(
		["read", "grep", "find"],
		[
			{ name: "grep", description: "Grep file contents. Smart-case." },
			{ name: "ffgrep", description: "Grep file contents. Smart-case." },
		],
	);

	expect(pruneResurrectedFffTools(fake.api)).toBe(false);
	expect(fake.setCalls).toBe(0);
});
