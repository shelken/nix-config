/** 纯内存单元测试 — 仅验证 sanitizeText 的标签重命名逻辑。 */

import { describe, expect, it } from "bun:test";
import { sanitizeText } from "./antigravity-fix.ts";

describe("antigravity-fix — sanitizeText", () => {
  it("重命名连字符标签（开/闭标签与正文均保留）", () => {
    const text = "<system-conventions>\nRFC 2119: MUST.\n</system-conventions>";
    expect(sanitizeText(text)).toBe("<conventions>\nRFC 2119: MUST.\n</conventions>");
  });

  it("重命名下划线变体", () => {
    expect(sanitizeText("<system_conventions>x</system_conventions>")).toBe(
      "<conventions>x</conventions>",
    );
  });

  it("重命名 system-directive 敏感词（含正文中字面引用）", () => {
    expect(sanitizeText("`<system-directive>` remains a directive")).toBe(
      "`<directive>` remains a directive",
    );
    expect(sanitizeText("<system_directive>x</system_directive>")).toBe("<directive>x</directive>");
  });

  it("无敏感词时原样返回", () => {
    expect(sanitizeText("plain text")).toBe("plain text");
  });
});
