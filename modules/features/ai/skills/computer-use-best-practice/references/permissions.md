# 驱动身份与 TCC 授权

用 `cua-driver serve` 在终端里直接启动时，TCC 归属终端进程，Accessibility 与 Screen Recording 都会缺失，每次调用弹出授权闸门。此时 `get_window_state` 仍返回结构，但截图落盘失败，脚本报 `未能取得有效图片`。

以 App 身份启动即可带上已有授权：

```bash
open -n -g -a CuaDriver --args serve        # 以 App 身份启动守护进程
cua-driver permissions grant                # 授权并验证
cua-driver permissions status               # 只读复核，不弹窗
```

`computer-use` 自身不启动驱动、不申请权限，只如实报告失败。
