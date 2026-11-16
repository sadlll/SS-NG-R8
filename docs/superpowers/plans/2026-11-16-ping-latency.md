# Ping Latency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 显示节点 ICMP RTT，独立保留真实代理可用性并发布更新。
**Architecture:** PingProbe 产生有目标地址的 RTT 测量；ProxyTestResult 分离 RTT 与 HTTPS 耗时。现有批处理收集两项结果，菜单和最快节点使用正确指标。
**Tech Stack:** Swift 5、Foundation、macOS ping/ping6、AppKit、Sparkle。
**Spec:** docs/superpowers/specs/2026-11-16-ping-latency-design.md

## Global Constraints

- macOS 14+ / Apple Silicon；不新增依赖；不修改正式代理或网络配置。
- ICMP 不可用不能导致 HTTPS 验证成功的节点被判不可用。
- HTTP/TLS 验证保持原有规则；取消和进程截止时间继续有效。

## Review Focus

- IPv6 summary 与 IPv4 统计格式不同；两者都解析。
- ping 可能部分丢包或完全无回复；只使用有效统计。
- 域名和用户输入不能变为命令选项；仅向 ping 传递已验证的数字 IP。
- ICMP 与代理成功组合的四种状态，菜单不能混淆指标。
- 排序/最快节点不能重新使用 HTTPS 总耗时。

## Task 1: 独立采集与显示

**Files:** Diagnostics/PingProbe.swift、ProxyTestResult.swift、Package.swift、project.pbxproj；ServerProfile.swift、PingClient.swift、MainMenuManager.swift；CLI、测试和本地化。
**Interfaces:** PingProbe.measure(host:) -> PingMeasurement；ProxyTestResult.requestDuration、ping、networkLatency、isProxyAvailable。

- [x] 先使模型测试证明没有 ping 时旧代码错误显示 HTTPS 数值。
- [x] 写 PingProbe IPv4/IPv6/丢包/异常输出测试与 loopback 实测测试，运行确认缺少实现。
- [x] 实现有界 ICMP 测量、独立结果、菜单与排序；补齐四种状态和最快节点回归。
- [x] 运行 swift test、test_app_model、真实节点 CLI 对照、Release 构建和 updater model；独立审查。

## Task 2: 发布和安装

- [ ] 递增版本、构建号，更新说明；签名和打包验证。
- [ ] 提交并推送标签，检查 GitHub CI，发布签名更新。
- [ ] 使用官方 Sparkle 流程更新本机，核验版本、签名及配置保留。
