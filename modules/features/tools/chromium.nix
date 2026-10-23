# brave/chromium 浏览器扩展（可选功能，未加入任何角色）
# 程序本身由 brew 安装，这里只声明受管扩展
{
  flake.modules.homeManager.chromium =
    { ... }:
    {
      programs.brave = {
        enable = false;
        extensions = [
          { id = "bpoadfkcbjbfhfodiogcnhhhpibjhbnh"; } # 沉浸式翻译
          { id = "pejdijmoenmkgeppbflobdenhhabjlaj"; } # icloud 密钥
          { id = "bcjindcccaagfpapjjmafapmmgkkhgoa"; } # json formatter
          { id = "gebbhagfogifgggkldgodflihgfeippi"; } # Return YouTube Dislike
          { id = "clngdbkpkpeebahjckkjfobafhncgmne"; } # stylus
          { id = "pncfbmialoiaghdehhbnbhkkgmjanfhe"; } # uBlacklist
          { id = "cjpalhdlnbpafiamejdnhcphjbkeiagm"; } # uBlock Origin
          { id = "onnepejgdiojhiflfoemillegpgpabdm"; } # V2EX Polish
          { id = "dhdgffkkebhmkfjojejmpbldmpobfkfo"; } # 篡改猴
        ];
      };
    };
}
