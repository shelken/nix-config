## 备忘

- `mylib.scanPaths` 将深入一级目录下读取default.nix
- 该目录下的子目录的所有配置都应该使用`options`和`config`结合能够开关，默认导入所有。本目录下的配置（通用配置）默认都导入
