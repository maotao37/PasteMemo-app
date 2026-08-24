Viewed dev.sh:1-81

在本地 Mac 上编译 PasteMemo，有以下几种最常用的方式：

---

### 1. 快速编译（开发模式）
在终端中进入项目根目录：
```bash
# 仅编译代码
swift build
# 或者
make build
```

---

### 2. 编译并直接运行 App（本地调试）
```bash
# 编译并在本地直接启动运行 PasteMemo
swift run
# 或者
make run
```

> 💡 **热重载开发模式**：运行 `make dev`，脚本会监听代码修改，每次保存文件后会自动重新编译并重启 App。

---

### 3. 本地打包出 `.app` 和 `.dmg` 安装包
如果你想在本地生成正式的 `.app` 和可分发的 `.dmg` 文件：
```bash
# 方式一：使用 Makefile（推荐）
make package VERSION=2.0.0

# 方式二：直接执行打包脚本
VERSION=2.0.0 ./scripts/package.sh
```
* 打包完成后，产物会存放在项目根目录的 **`dist/`** 文件夹中：
  - `dist/PasteMemo.app`（直接双击即可运行）
  - `dist/PasteMemo-2.0.0-arm64.dmg`（DMG 安装镜像包）

---

### 4. 使用 Xcode 打开项目可视化开发
PasteMemo 是标准的 SwiftPM 项目，可以直接用 Xcode 打开：
```bash
# 打开 Package.swift 进入 Xcode
open Package.swift
```
在 Xcode 中：
- 按 **`⌘B`** 进行编译
- 按 **`⌘R`** 编译并启动调试

---

### 5. 运行单元测试与代码检查
```bash
# 运行单元测试
swift test
# 或者
make test

# 运行代码规范与静态检查
make check
```

---
