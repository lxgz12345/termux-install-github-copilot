# Termux Install GitHub Copilot

在 Android ARM64（Termux）上一键编译并部署 [GitHub Copilot CLI](https://githubnext.com/projects/copilot-cli/)。

> 适用于官方 Copilot CLI 不包含 `pty.node` 和 `ripgrep` ARM64 预构建文件的情况。

---

## 背景

GitHub Copilot CLI (`@github/copilot`) 依赖两个原生组件：

| 组件 | 用途 |
|------|------|
| `pty.node` | 启用 bash 工具（交互式终端） |
| `rg`（ripgrep） | 代码搜索工具 |

官方预构建版本不含 `android-arm64` 目标，因此在 Termux 中需要从源码编译。

---

## 测试环境

| 项目 | 版本 |
|------|------|
| Termux | Google Play 版 `googleplay.2026.02.11` |
| 架构 | Android ARM64 |

> ⚠️ 注意：[Termux 官方](https://termux.dev/) 推荐使用 F-Droid 版本，Google Play 版本可能存在功能限制。本脚本已在 Google Play 版本上验证可用。

---

## 前置要求

- Android 设备，已安装 Termux（Google Play 版 `googleplay.2026.02.11` 或更高）
- 可用的网络连接
- GitHub 账号（用于后续登录 Copilot CLI）

---

## 使用方法

```bash
# 1. 克隆本仓库
git clone https://github.com/lxgz12345/termux-install-github-copilot.git
cd termux-install-github-copilot

# 2. 赋予执行权限
chmod +x build-pty.sh

# 3. 运行脚本
./build-pty.sh
```

脚本执行完成后，重启 Termux 或重新打开终端，然后运行：

```bash
gh copilot --version   # 确认 Copilot CLI 已安装
copilot                # 启动 Copilot CLI
```

---

## 脚本执行步骤

| 步骤 | 内容 |
|------|------|
| **[1/7]** 更新软件包 | `pkg update && pkg upgrade` |
| **[2/7]** 安装依赖 | `nodejs-lts python make clang binutils ripgrep gh git` |
| **[3/7]** 安装 Copilot CLI | `npm install -g @github/copilot@1.0.42` |
| **[4/7]** 修复 ripgrep 链接 | 创建 `android-arm64/rg` 软链接指向系统 `rg` |
| **[5/7]** 准备编译工作区 | 初始化 `node-gyp` 构建环境 |
| **[6/7]** 修补 common.gypi | 移除 Android NDK 依赖（Termux 不需要） |
| **[7/7]** 编译 node-pty | 依次尝试多个版本，成功后部署 `pty.node` |

---

## 部署路径

```
$PREFIX/lib/node_modules/@github/copilot/
├── prebuilds/android-arm64/pty.node   ← 编译产物
└── ripgrep/bin/android-arm64/rg       ← ripgrep 软链接
```

---

## 常见问题

**Q: 脚本报错"无法找到 common.gypi"**  
A: 请检查网络连接，脚本首次运行需要下载 Node.js 头文件。

**Q: 所有版本 node-pty 均编译失败**  
A: 查看 `~/pty-build/build-*.log` 中的详细错误信息，并确认 `clang` 版本：`clang --version`。

**Q: 编译成功但 bash 工具仍不可用**  
A: 完全关闭并重启 Termux 后重试。

---

## 许可证

[MIT](LICENSE)
