/**
 * alt+shift+x：剪切输入框文本到系统剪贴板。
 * 兼容 Kitty CSI-u、modifyOtherKeys、ESC+X、macOS Option+Shift+X 字符。
 */

import { copyToClipboard } from "@earendil-works/pi-coding-agent";

// Kitty CSI-u：x=120；mod 编码 1+bits（shift=1 alt=2）→ alt+shift=4
const KITTY_CUT = new RegExp(String.raw`^\x1b\[120(?::\d*)*(?::\d*)?;4(?::\d+)?u$`);

export function isCutInput(data: string): boolean {
  if (KITTY_CUT.test(data)) return true;
  if (data === "\x1b[27;4;120~") return true;
  if (data === "\x1bX") return true;
  if (data === "˛") return true;
  return false;
}

async function cut(ui: {
  getEditorText: () => string;
  setEditorText: (text: string) => void;
  notify?: (message: string, type?: "info" | "warning" | "error") => void;
  showStatus?: (message: string) => void;
}): Promise<void> {
  const text = ui.getEditorText();
  if (!text) return;
  await copyToClipboard(text);
  ui.setEditorText("");
  if (ui.showStatus) {
    ui.showStatus("Cut editor text");
  } else if (ui.notify) {
    ui.notify("Cut editor text", "info");
  }
}

export default function copyCutExtension(pi: any): void {
  pi.registerShortcut("alt+shift+x", {
    description: "Cut editor text to clipboard",
    handler: async (ctx: any) => {
      await cut(ctx.ui);
    },
  });

  pi.on("session_start", async (_event: any, ctx: any) => {
    if (!ctx.hasUI || !ctx.ui.onTerminalInput) return;

    ctx.ui.onTerminalInput((data: string) => {
      if (!isCutInput(data)) return;
      void cut(ctx.ui).catch((err: unknown) => {
        const message = err instanceof Error ? err.message : String(err);
        if (ctx.ui.showWarning) {
          ctx.ui.showWarning(`Cut failed: ${message}`);
        } else if (ctx.ui.notify) {
          ctx.ui.notify(`Cut failed: ${message}`, "error");
        }
      });
      return { consume: true };
    });
  });
}
