# Agent Sandbox

基于 microsandbox（libkrun）构建的常驻 Linux 微 VM 沙箱环境，为 AI Agent（OMP、Pi 等）提供安全隔离、免污染宿主的执行环境。

## 常用命令

所有操作通过 Home Manager 导出的 `sb-default` CLI 完成：

### 1. 启动与停止

- **启动沙箱**（首次执行自动创建虚拟机，后续执行仅确保启动）
  ```bash
  sb-default up
  ```

- **查看运行状态**
  ```bash
  sb-default status
  ```

- **停止沙箱**（停止后台 VM，保留磁盘与数据卷）
  ```bash
  sb-default down
  ```

- **销毁沙箱**（删除 VM 实例，持久化命名卷保持保留）
  ```bash
  sb-default rm
  ```

### 2. 运行与交互

- **运行 OMP（文本模式）**
  ```bash
  sb-default exec omp --version
  ```

- **运行 OMP（交互式 TUI）**
  ```bash
  sb-default exec -t omp
  ```

- **进入沙箱 Bash Shell**
  ```bash
  sb-default shell
  ```

- **SSH 运维通道**
  ```bash
  sb-default ssh
  ```

## 目录与数据流

| 路径 | 来源 / 属性 | 说明 |
|---|---|---|
| `/workspace` | 宿主 `~/Code`（读写） | 日常项目开发目录 |
| `/nix/store` | 宿主 `/nix/store`（只读） | 零拷贝继承 Linux CLI 工具链与 OMP |
| `/data` | 独占 ext4 命名卷（读写） | 存放 SQLite 数据库、会话记录与状态，防跨内核并发损坏 |
| `/root/.omp/agent` | 宿主 `~/.omp/sandbox-config`（只读） | 纯配置集整树挂载（零数据库，彻底避免锁冲突） |
| `/root/.agents` | 宿主 `~/.agents`（只读） | 继承宿主 Skills 与 Prompts |

## 网络与凭据

- **凭据注入**：外层通过 `sec-run` 注入环境变量，msb 原生 secrets 代理拦截并按域名白名单放行，不向沙箱泄露宿主 SSH 私钥
- **本地服务访问**：虚拟机内访问宿主监听的服务（如本地模型代理），统一使用内置域名 `host.microsandbox.internal`
