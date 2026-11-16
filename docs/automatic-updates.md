# 应用内更新

点击状态栏菜单中的“帮助 → 检查并安装更新…”，按更新窗口提示下载并安装。安装完成后应用重新启动，服务器配置、当前节点和代理设置保存在用户目录中并继续使用。2.0.x 需要先手动安装一次 2.1.0，之后可在应用内升级。

更新来源是本仓库 GitHub 正式发行版的 `appcast.xml`，下载地址固定到对应版本标签。Sparkle 2.10.1 负责检查、下载、安装及重启。更新列表必须有有效签名，更新 ZIP 必须通过应用内公钥的 Ed25519 校验后才能解压。默认不自动下载安装；原有“启动时检查更新”选项仍然有效。

## 发布维护

1. 同步修改 `Info.plist` 的版本号、递增构建号以及项目的 `MARKETING_VERSION`，添加 `docs/releases/v版本.md`。
2. 推送版本标签。Actions 构建并签名应用，检查更新菜单，生成 DMG、更新 ZIP、SHA-256 文件及签名后的 `appcast.xml`，上传为草稿发行版。
3. 核验产物和版本后发布草稿，并设为 latest。旧客户端即可发现更新。

Actions 使用仓库 secret `SPARKLE_PRIVATE_KEY`；本地打包使用登录钥匙串账户 `sadlll.SS-NG-R8.updates`。私钥不进入仓库或发布产物。不要重新生成密钥，除非按 Sparkle 的密钥轮换流程安排客户端迁移。应用签名与更新签名相互独立，当前应用本体使用 ad-hoc 签名且未经 Apple 公证。

本地检查：先构建 Release，再运行 `script/test_updater_model.sh`、`script/sign_app.sh` 和 `script/package_update.sh App.app 输出目录 v版本`。打包会验证正常更新，并验证被篡改的包、被篡改的列表和错误公钥均被拒绝。
