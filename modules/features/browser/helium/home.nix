# Helium 受管扩展：往数据目录的 External Extensions 写声明文件，各 profile 启动时按需安装
# 并提供 helium-sync-ext，把 Default 里这些扩展的设置复制到其他 profile
{
  flake.modules.homeManager.helium =
    { lib, pkgs, ... }:
    let
      externalExtensionsDir = "Library/Application Support/net.imput.helium/External Extensions";

      # Helium 把 Web Store 更新地址换成了这个占位符，运行时再改写为自家代理；
      # 写 Google 原地址会被拦截，扩展装不上（Helium 0.21 实测）
      webstoreUpdateUrl = "https://update-url-to-be-replaced.qjz9zk";

      extensions = {
        # 最小化原则; 一旦引入再注释 会立刻在下次重新打开时移除掉.
        # pejdijmoenmkgeppbflobdenhhabjlaj = "iCloud 密码";
        # bpoadfkcbjbfhfodiogcnhhhpibjhbnh = "沉浸式翻译";
        # bcjindcccaagfpapjjmafapmmgkkhgoa = "JSON Formatter";
        # clngdbkpkpeebahjckkjfobafhncgmne = "Stylus";
        # pncfbmialoiaghdehhbnbhkkgmjanfhe = "uBlacklist";
        # onnepejgdiojhiflfoemillegpgpabdm = "V2EX Polish";
        # dhdgffkkebhmkfjojejmpbldmpobfkfo = "篡改猴";
        # hlkenndednhfkekhgcdicdfddnkalmdm = "Cookie-Editor";
        # bkcoalnaffahmgeimpeefbnddgelfokd = "GitHub DeepWiki";
        dgdbdodafgaeifgajaajohkjjgobcgje = "GeoSpoof";
        pkehgijcmpdhfbdbbnkijodmdjhbjlgp = "隐私獾";
      };
      syncExtStorage = pkgs.writeShellApplication {
        name = "helium-sync-ext";
        text =
          "ids=(${lib.escapeShellArgs (lib.attrNames extensions)})\n"
          + builtins.readFile ./sync-ext-storage.sh;
      };
    in
    {
      home.packages = [ syncExtStorage ];

      home.file = lib.mapAttrs' (
        id: _:
        lib.nameValuePair "${externalExtensionsDir}/${id}.json" {
          text = builtins.toJSON { external_update_url = webstoreUpdateUrl; };
        }
      ) extensions;
    };
}
