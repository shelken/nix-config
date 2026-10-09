/** 纯内存单元测试 — 验证 OpenCode Zen free-tier headers 与工具注入逻辑。 */

import { describe, expect, it } from "bun:test";
import zenFreeTierHeaders, {
  canonicalizeSessionId,
  injectZenTools,
  isZenUrl,
  OPENCODE_SESSION_RE,
  OPENCODE_USER_AGENT,
  patchZenHeaders,
  rewriteZenUrl,
  ZEN_REQUIRED_TOOL_NAMES,
} from "./zen-free-tier-headers.ts";

describe("zen-free-tier-headers — canonicalizeSessionId", () => {
  it("已符合规范的 session id 直接放行", () => {
    const valid = "ses_0123456789abCDEFGHIJ012345";
    expect(canonicalizeSessionId(valid)).toBe(valid);
  });

  it("非规范 session id 规范化为 ses_<12hex><14base62>", () => {
    const canonical = canonicalizeSessionId("my-custom-session-123");
    expect(OPENCODE_SESSION_RE.test(canonical)).toBe(true);
    // 幂等性：同一输入产生相同输出
    expect(canonicalizeSessionId("my-custom-session-123")).toBe(canonical);
  });

  it("不同输入产生不同的 session id", () => {
    const a = canonicalizeSessionId("session-a");
    const b = canonicalizeSessionId("session-b");
    expect(a).not.toBe(b);
  });
});

describe("zen-free-tier-headers — isZenUrl & rewriteZenUrl", () => {
  it("识别 opencode.ai 及其子域名", () => {
    expect(isZenUrl("https://opencode.ai/zen/v1/chat/completions")).toBe(true);
    expect(isZenUrl("https://api.opencode.ai/inference/openai/v1")).toBe(true);
    expect(isZenUrl("https://api.anthropic.com/v1/messages")).toBe(false);
    expect(isZenUrl("not-a-valid-url")).toBe(false);
  });

  it("将遗留的 /zen/ 路径透明重写为 /inference/openai/", () => {
    const res = rewriteZenUrl("https://opencode.ai/zen/v1/chat/completions");
    expect(res.rewritten).toBe(true);
    expect(res.url).toBe("https://opencode.ai/inference/openai/v1/chat/completions");
  });

  it("非 /zen/ 路径不重写", () => {
    const res = rewriteZenUrl("https://opencode.ai/inference/openai/v1/chat/completions");
    expect(res.rewritten).toBe(false);
    expect(res.url).toBe("https://opencode.ai/inference/openai/v1/chat/completions");
  });

  it("ZEN_REWRITE_URL=0 时跳过重写", () => {
    const prev = process.env.ZEN_REWRITE_URL;
    try {
      process.env.ZEN_REWRITE_URL = "0";
      const res = rewriteZenUrl("https://opencode.ai/zen/v1/chat/completions");
      expect(res.rewritten).toBe(false);
      expect(res.url).toBe("https://opencode.ai/zen/v1/chat/completions");
    } finally {
      if (prev === undefined) {
        delete process.env.ZEN_REWRITE_URL;
      } else {
        process.env.ZEN_REWRITE_URL = prev;
      }
    }
  });
});

describe("zen-free-tier-headers — patchZenHeaders", () => {
  it("为缺少 session 的请求补齐桌面客户端标识与规范 session", () => {
    const headers = new Headers();
    patchZenHeaders(headers);

    expect(headers.get("user-agent")).toBe(OPENCODE_USER_AGENT);
    expect(headers.get("x-opencode-client")).toBe("desktop");
    const session = headers.get("x-opencode-session");
    expect(session).toBeTruthy();
    expect(OPENCODE_SESSION_RE.test(session ?? "")).toBe(true);
  });

  it("保留原有的 claude-cli OAuth User-Agent 指纹", () => {
    const headers = new Headers({
      "user-agent": "claude-cli/1.0.0 (darwin; arm64)",
    });
    patchZenHeaders(headers);
    expect(headers.get("user-agent")).toBe("claude-cli/1.0.0 (darwin; arm64)");
  });

  it("重写现有 session_id 为规范 OpenCode 格式", () => {
    const headers = new Headers({
      session_id: "omp-session-abc",
    });
    patchZenHeaders(headers);
    const session = headers.get("x-opencode-session");
    expect(session).toBe(canonicalizeSessionId("omp-session-abc"));
  });
});

describe("zen-free-tier-headers — injectZenTools", () => {
  it("当缺失核心工具时自动注入 bash 和 read 的 stub", () => {
    const payload = JSON.stringify({
      messages: [{ role: "user", content: "hello" }],
      tools: [],
    });

    const res = injectZenTools("https://opencode.ai/inference/openai/v1/chat/completions", payload);
    expect(res.present).toBe(0);
    expect(res.injected).toEqual(ZEN_REQUIRED_TOOL_NAMES);

    const parsed = JSON.parse(res.text) as {
      tools: Array<{ type: string; function?: { name: string } }>;
    };
    expect(parsed.tools.length).toBe(2);
    expect(parsed.tools.map((t) => t.function?.name)).toEqual(["bash", "read"]);
  });

  it("当已有足够的核心工具时不重复注入", () => {
    const payload = JSON.stringify({
      tools: [
        { type: "function", function: { name: "bash" } },
        { type: "function", function: { name: "read" } },
      ],
    });

    const res = injectZenTools("https://opencode.ai/inference/openai/v1/chat/completions", payload);
    expect(res.present).toBe(2);
    expect(res.injected).toEqual([]);
    expect(res.text).toBe(payload);
  });

  it("当 tool_choice 为 required / any 时不注入 stub，防止模型误调未注册工具", () => {
    const payload = JSON.stringify({
      tools: [],
      tool_choice: "required",
    });

    const res = injectZenTools("https://opencode.ai/inference/openai/v1/chat/completions", payload);
    expect(res.injected).toEqual([]);
    expect(res.text).toBe(payload);
  });

  it("非法 JSON 原样放行", () => {
    const invalid = "not a json";
    const res = injectZenTools("https://opencode.ai/inference/openai/v1/chat/completions", invalid);
    expect(res.text).toBe(invalid);
    expect(res.injected).toEqual([]);
  });
});

describe("zen-free-tier-headers — extension entrypoint & fetch wrapping", () => {
  it("插件入口正常初始化并记录日志", () => {
    let logged = "";
    zenFreeTierHeaders({
      logger: {
        info: (msg) => {
          logged = String(msg);
        },
      },
    });
    expect(logged).toContain("fetch patch active");
  });

  it("globalThis.fetch 拦截 opencode.ai 并注入请求头与重写 URL", async () => {
    const intercepted: { url?: string; headers?: Headers; body?: string } = {};

    // 临时接管底层 globalThis.fetch，验证 monkeypatch 行为
    const origFetch = globalThis.fetch;
    try {
      // 模拟上游 fetch
      const mockFetch: typeof fetch = async (input, init) => {
        intercepted.url = typeof input === "string" ? input : (input as Request).url;
        intercepted.headers = new Headers(init?.headers);
        intercepted.body = typeof init?.body === "string" ? init.body : undefined;
        return new Response(JSON.stringify({ ok: true }), { status: 200 });
      };

      // 重新安装 patch
      const g = globalThis as Record<string, unknown>;
      delete g.__ompZenFreeTierHeadersPatched;
      globalThis.fetch = mockFetch;
      zenFreeTierHeaders();

      // 发起对 legacy zen url 的请求
      const resp = await fetch("https://opencode.ai/zen/v1/chat/completions", {
        method: "POST",
        headers: { "x-opencode-session": "raw-session-id" },
        body: JSON.stringify({
          tools: [],
        }),
      });

      expect(resp.status).toBe(200);
      expect(intercepted.url).toBe("https://opencode.ai/inference/openai/v1/chat/completions");
      expect(intercepted.headers?.get("user-agent")).toBe(OPENCODE_USER_AGENT);
      expect(intercepted.headers?.get("x-opencode-client")).toBe("desktop");
      expect(intercepted.headers?.get("x-opencode-session")).toBe(
        canonicalizeSessionId("raw-session-id"),
      );

      // 验证 body 注入了工具
      const parsedBody = JSON.parse(intercepted.body ?? "{}") as {
        tools?: Array<{ function?: { name: string } }>;
      };
      expect(parsedBody.tools?.map((t) => t.function?.name)).toEqual(["bash", "read"]);

      // 非 opencode.ai 的外部请求原样穿透
      const nonZenResp = await fetch("https://example.com/api", {
        headers: { "user-agent": "custom-agent" },
      });
      expect(nonZenResp.status).toBe(200);
      expect(intercepted.url).toBe("https://example.com/api");
      expect(intercepted.headers?.get("user-agent")).toBe("custom-agent");
    } finally {
      // 还原 globalThis.fetch 与补丁状态
      const g = globalThis as Record<string, unknown>;
      globalThis.fetch = origFetch;
      g.__ompZenFreeTierHeadersPatched = true;
    }
  });
});
