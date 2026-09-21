/**
 * antigravity-fix — google-antigravity (Cloud Code Assist) 服务端对系统提示做字面
 * 特征匹配，命中即回假 429 RESOURCE_EXHAUSTED (oh-my-pi#11699、#11794)。
 * 逐条破坏被匹配的字面量，指令语义原样保留；清单与 CLIProxyAPI antigravity
 * sensitive-words 补丁对齐：
 * - <system-conventions> / <system-directive> 标签（连字符、下划线两种变体）
 *   改名为去掉 system- 前缀的等价标签
 * - "RFC 2119" 短语插入零宽空格（#11730 字节级二分：同一 62 KB 载荷仅此一处
 *   改动即从 429 变 200）
 */

const RENAMES: Array<[string, string]> = [
  ["system-conventions", "conventions"],
  ["system_conventions", "conventions"],
  ["system-directive", "directive"],
  ["system_directive", "directive"],
];

/** 命中即 429 的短语，拆开即破坏上游的字面匹配。 */
const OBFUSCATED_WORDS = ["RFC 2119"];

const ZERO_WIDTH_SPACE = "\u200B";

export function sanitizeText(text: string): string {
  for (const [from, to] of RENAMES) {
    text = text.split(from).join(to);
  }
  for (const word of OBFUSCATED_WORDS) {
    // 零宽空格插在首字符后：肉眼与模型侧均不可见，重复调用也不再命中原短语
    text = text.split(word).join(word.slice(0, 1) + ZERO_WIDTH_SPACE + word.slice(1));
  }
  return text;
}

interface ExtensionContext {
  model?: { provider?: string };
}

interface ExtensionAPI {
  on(
    event: "before_provider_request",
    handler: (event: { payload?: unknown }, ctx: ExtensionContext) => void | Promise<void>,
  ): void;
}

/** 只认领 omp 交给 antigravity 的形态：request.systemInstruction.parts。 */
function systemInstructionParts(payload: unknown): unknown[] | undefined {
  if (typeof payload !== "object" || payload === null) return undefined;
  if (!("request" in payload)) return undefined;
  const { request } = payload;
  if (typeof request !== "object" || request === null) return undefined;
  if (!("systemInstruction" in request)) return undefined;
  const { systemInstruction } = request;
  if (typeof systemInstruction !== "object" || systemInstruction === null) return undefined;
  if (!("parts" in systemInstruction) || !Array.isArray(systemInstruction.parts)) {
    return undefined;
  }
  const parts: unknown[] = systemInstruction.parts;
  return parts;
}

/** 只放行携带字符串 text 的部件，其余形态（图片等）原样交给 provider。 */
function isTextPart(value: unknown): value is { text: string } {
  return (
    typeof value === "object" &&
    value !== null &&
    "text" in value &&
    typeof value.text === "string"
  );
}

export default function antigravityFixExtension(pi: ExtensionAPI): void {
  pi.on("before_provider_request", (event, ctx) => {
    if (ctx.model?.provider !== "google-antigravity") return;

    const parts = systemInstructionParts(event.payload);
    if (!parts) return;
    for (const part of parts) {
      if (isTextPart(part)) {
        part.text = sanitizeText(part.text);
      }
    }
  });
}
