/** 纯内存单元测试 — 仅验证 sanitizeText 的标签重命名与敏感短语拆分逻辑。 */

import { describe, expect, it } from "bun:test";
import { sanitizeText } from "./antigravity-fix.ts";

const ZERO_WIDTH_SPACE = "\u200B";

describe("antigravity-fix — sanitizeText", () => {
  it("重命名连字符标签（开/闭标签与正文均保留）", () => {
    const text = "<system-conventions>\nRFC 2119: MUST.\n</system-conventions>";
    expect(sanitizeText(text)).toBe(
      `<conventions>\nR${ZERO_WIDTH_SPACE}FC 2119: MUST.\n</conventions>`,
    );
  });

  it("重命名下划线变体", () => {
    expect(sanitizeText("<system_conventions>x</system_conventions>")).toBe(
      "<conventions>x</conventions>",
    );
  });

  it("重命名 system-directive 敏感词（含正文中字面引用，正文其余部分不动）", () => {
    expect(sanitizeText("`<system-directive>` remains a system directive")).toBe(
      "`<directive>` remains a system directive",
    );
    expect(sanitizeText("<system_directive>x</system_directive>")).toBe("<directive>x</directive>");
  });

  it("拆分 RFC 2119 短语，同句其余内容逐字保留", () => {
    const text = "RFC 2119: MUST, REQUIRED, SHOULD, RECOMMENDED, MAY, OPTIONAL. `NEVER` = `MUST NOT`.";
    expect(sanitizeText(text)).toBe(
      `R${ZERO_WIDTH_SPACE}FC 2119: MUST, REQUIRED, SHOULD, RECOMMENDED, MAY, OPTIONAL. \`NEVER\` = \`MUST NOT\`.`,
    );
  });

  it("重复处理幂等（零宽空格不叠加）", () => {
    const once = sanitizeText("<system-conventions>RFC 2119: MUST.</system-conventions>");
    expect(sanitizeText(once)).toBe(once);
  });

  it("无敏感词时原样返回", () => {
    expect(sanitizeText("plain text")).toBe("plain text");
  });
});
