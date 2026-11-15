# 代理请求测试与连接路径

菜单中的“服务器代理请求测试”会为每个节点启动独立的临时 ss-local，通过它的 SOCKS5 连接请求 `https://www.gstatic.com/generate_204`。只有 TLS 验证成功且返回 HTTP 204，才显示耗时；错误密码、代理无法转发、超时或其他 HTTP 状态均显示“请求失败”。每次请求最多 10 秒，失败后重试一次；最多并行测试 3 个节点。

示例：`linodejp (…) - 324.059 ms · 中继`。毫秒数是 HTTPS 请求总耗时，包含连接、TLS 和服务器响应，**不是 ICMP 往返延迟或下载带宽**。悬停可查看目标地址、测试时间、路径来源和失败说明。路径为测试时快照，重新测试会更新。

- Tailscale：按解析得到的节点 IP 匹配本机 `status --json`，识别当前直连端点、DERP 或 Peer Relay。离线、空闲且没有路径、CLI 不可用等情况显示“路径未知”；不会仅凭 DERP 地区字段认定中继。
- ZeroTier：按路由接口、网络和邻居 MAC 对应到节点 ID，再读取该节点的实际路径。请求成功但没有活动直连路径时显示“中继”。路由网关、桥接、缺少映射等情况显示“路径未知”。
- 普通网络：通过普通接口成功连接服务器时显示“直连”；其他 VPN 接口或含混的多地址结果显示“路径未知”。

Tailscale 查询显式设置子进程环境变量 `TAILSCALE_BE_CLI=1`，确保从 Finder、Dock 或登录启动时也使用 CLI 模式；不会修改全局环境或 Tailscale 配置。参见 [Tailscale 官方 CLI 说明](https://tailscale.com/docs/reference/tailscale-cli?tab=macos)。

## macOS 27 的 ZeroTier 节点关联

macOS 27 会对缺少 Network Topology Observation 签名能力的程序隐藏 ARP 数据。这个项目可生成未公证的本地构建，因此提供不依赖 ARP 的显式关联：

1. 打开“服务器设置”，选中目标节点。
2. 点击窗口左下角“ZeroTier 节点…”，填写目标服务器的 **10 位节点 ID**。
3. 点击“确定”保存服务器设置，再运行代理请求测试。

节点 ID 可在目标服务器执行 `zerotier-cli info` 获取，或在 ZeroTier 管理界面查看。留空可恢复自动识别。关联只用于路径查询，不改变代理参数、网络成员关系或路由；更换服务器地址后请更新该关联。若系统可读取的邻居证据与手工关联冲突，结果仍为“未知”。

Apple 对这一限制的说明：[macOS 27 ARP 与拓扑观测能力](https://developer.apple.com/forums/thread/822025?page=2)。

## 构建与验证

```sh
swift test
./script/test_app_model.sh
./script/build_and_run.sh --build-only
./script/build_and_run.sh --verify
```

应用输出在 `build/Build/Products/Debug/ShadowsocksX-NG.app`。`--verify` 会退出当前客户端并启动新构建；`--build-only` 只编译。构建脚本将旧登录助手的最低系统版本覆盖为 macOS 14，以兼容当前 SDK。

可独立测试已有配置，保留当前应用及选中节点：

```sh
mkdir -p build/checks
swiftc -swift-version 5 Diagnostics/*.swift script/check_profiles.swift -o build/checks/check_profiles
build/checks/check_profiles /tmp/proxy-results.json
# 可选：只为本轮测试提供节点关联，不写入设置
build/checks/check_profiles /tmp/proxy-results.json example.internal=0123456789
```

输出不包含密码；临时配置目录为 0700、配置文件为 0600，完成、失败或正常退出时会清理。测试不修改正式代理的配置、启动任务或系统代理设置。
