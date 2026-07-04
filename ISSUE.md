# iOS TLS 不可用问题记录

来源：RingoRTC App（`~/work/ringortc/app`）接入 `io.github.davidepianca98:kmqtt-client:1.0.0`（Maven Central 发布版）时，在 iOS Simulator 上发现的运行时问题。记录下来供本 fork 后续从源码重新构建 `kmqtt-common`/`kmqtt-client` 时参考。

## 问题现象

Android/JVM 端一切正常（`kmqtt-client`/`kmqtt-common` 走 JVM 实现）。iOS 端编译、链接均成功，但**运行时**任何一次 TLS 连接尝试都会立即失败，报错：

```
Function 'BIO_s_mem' can not be called: No function found for symbol 'openssl/BIO_s_mem|BIO_s_mem(){}[100]'.
This looks like a cinterop-generated library issue. It could happen if there is a transitive dependency
which uses cinterop and the resulting libraries are not binary compatible. Or there might be a cinterop
dependency generated with a different version of the Kotlin/Native compiler than the version used to
compile this binary. Please check that the project configuration is correct and has consistent versions
of all required dependencies. See https://youtrack.jetbrains.com/issue/KT-78062 for more details.
```

`MqttSignalingClient`（消费方代码）每次 `connect()` 都触发一次这个错误，`onConnected`/`onDisconnected` 都不会被调用，进入无限重连循环（表现为“一直连不上”，而不是崩溃）。

## 根因

`kmqtt-common/src/nativeInterop/openssl.def` 里 Apple 平台的 `compilerOpts`/`libraryPaths` **全部硬编码指向作者本机路径**：

```
compilerOpts.ios_arm64 = -I/Users/davide/Desktop/openssl/OpenSSL-for-iPhone/bin/iPhoneOS17.2-arm64.sdk/include
libraryPaths.ios_arm64 = /Users/davide/Desktop/openssl/OpenSSL-for-iPhone/bin/iPhoneOS17.2-arm64.sdk/lib
```

`Readme.md` 里对此的说明（第 55/153 行）是：

> If you are getting an error saying that OpenSSL hasn't been found, please copy the correct file from https://github.com/davidepianca98/KMQTT/tree/master/kmqtt-common/src/nativeInterop in your project's main directory.

这条说明只解决了“编译期报 OpenSSL not found”的场景（消费方在自己项目里重新跑 cinterop 时用）。但 **Maven Central 上发布的 `kmqtt-common`/`kmqtt-client` 预编译 klib 已经在作者本机把这次 cinterop 跑过一次并发布了产物**——消费方拿到手的不是源码，而是已经用作者本机 OpenSSL 生成好的 klib，Readme 的这条说明对“直接依赖 Maven 坐标”的用户不生效。

### 为什么“自己编译一份同版本 OpenSSL 再链接”也没用

已在 RingoRTC App 侧实测验证过以下方案**完全无效**：

1. 用 `OpenSSL-for-iPhone` 脚本编译**同一版本**（1.1.1w，跟 def 文件里写的完全一致）的 OpenSSL for iOS（device arm64 + simulator arm64）。
2. 打包成 XCFramework，通过 CocoaPods `vendored_frameworks` 接入最终 iOS App 的链接。
3. 确认 `xcodebuild` 链接命令行正确出现 `-lopenssl`，`Ld` 步骤无报错，整个 App 编译链接成功。
4. **运行时报错跟没做 1-3 之前一模一样**，`BIO_s_mem` 依然找不到。

结合错误信息引用的 [KT-78062](https://youtrack.jetbrains.com/issue/KT-78062)（标题 "K/N: diverged cinterop libraries"，JetBrains 官方 open/未修复，无 workaround）可以确认：

- Kotlin/Native 的 cinterop 机制里，对 C 符号（如 `BIO_s_mem`）的引用**不是**走传统的“符号名字符串”动态链接。
- klib 序列化的 IR 里，对 cinterop 符号的引用被编码成一个**跟本次 cinterop 生成过程强绑定的索引/指纹**（错误信息里的 `[100]` 就是这个索引），这个索引在 IR 反序列化阶段被查找，早于最终二进制的链接阶段。
- `kmqtt-common-iosarm64`/`kmqtt-common-iossimulatorarm64` 发布的 klib 内部依赖的那份 openssl cinterop 产物，索引是**作者本机那次 cinterop 运行**烘焙出来的。任何人（哪怕用完全相同版本、相同 header 布局的 OpenSSL）在自己机器上重新跑 cinterop，生成的都是一份**索引不同**的新 klib——链接器层面两边"符号名字符串"一样、能对上，但 Kotlin/Native 运行时要求的是"这个符号必须来自编译期认定的那个具体 cinterop 库"，索引对不上就在运行时报"符号找不到"。
- 这不是"缺库"问题，纯靠在消费方项目里补链接（CocoaPods/`vendored_frameworks`/`linkerOpts` 等任何方式）**无法修复**。

## 结论：Maven Central 发布的 iOS 预编译 klib 事实上不可用

对于任何不是作者本人机器环境的消费者，`kmqtt-client`/`kmqtt-common` 的 iOS/Apple-native target 目前**没有可用的 TLS 支持**——不是文档没写清楚，是发布产物本身的 cinterop 身份跟消费方环境天然不兼容。GitHub issues 里搜到的类似反馈（如 #14，Linux "Could not find openssl"）都是编译期找不到路径的配置问题，没有搜到已解决的、跟这个运行时符号索引不匹配等价的案例。

## 待办：从源码重新构建

既然本仓库就是 fork（`bigcat26/KMQTT`），可行路径是在 CI/发布流程里**自己跑一遍 cinterop 生成**，而不是依赖任何预先发布的 openssl klib：

1. 编译/vendor 一份适配当前 CI 机器路径的 OpenSSL 1.1.1w for Apple targets（`OpenSSL-for-iPhone` 或等价脚本），产出物路径不应再硬编码到某个人的 `/Users/xxx/Desktop`，改成相对本仓库根目录或 CI 环境变量可配置的路径。
2. 改写 `kmqtt-common/src/nativeInterop/openssl.def` 里所有 Apple target（`ios_arm64`/`ios_simulator_arm64`/`ios_x64`/`macos_*`/`tvos_*`/`watchos_*`）的 `compilerOpts`/`libraryPaths`，指向第 1 步产出的路径。
3. 用改好的 def 文件，在**同一次构建**里跑 `kmqtt-common` 的 cinterop + 编译 + `kmqtt-client` 依赖它一起编译（`build-klibs.sh` 已有的各 target `*Klib` task 列表可以复用），确保 openssl cinterop 产物和 kmqtt-common/kmqtt-client 的 klib 是同一次构建、同一个索引空间生成的。
4. 发布到内部/私有 Maven 仓库（或者 RingoRTC App 侧直接用 Gradle composite build / `includeBuild` 引入本仓库源码，不走已发布的 Maven 坐标），避免"消费方引入的是别人机器编译的 klib"这个根本问题再次出现。
5. 验证：在一台**没有装任何 OpenSSL、没有克隆过本仓库**的干净机器上，仅通过 Maven/composite build 拉取产物，跑一次真实的 iOS TLS MQTT 连接，确认不再报 `BIO_s_mem` 相关错误。

## 参考

- 触发问题的项目：RingoRTC App，`sdk/kmp` 模块（`io.github.davidepianca98:kmqtt-common`/`kmqtt-client:1.0.0` 依赖）
- Kotlin/Native 已知限制：https://youtrack.jetbrains.com/issue/KT-78062
- OpenSSL for iOS 编译脚本：https://github.com/x2on/OpenSSL-for-iPhone

## 处理结果（本 fork，2026-07-04）

### 编译期结论

验证确认：本仓库当前从源码编译 iOS klib（`./gradlew :kmqtt-common:iosArm64MainKlibrary` 等）**是成功的**。原因是 `kmqtt-common/build.gradle.kts` 并没有在构建中调用 cinterop 重新生成 openssl 绑定，而是直接把 `kmqtt-common/src/nativeInterop/openssl-*.klib`（作者本机已经跑过一次 cinterop 并提交进仓库的产物）当作普通文件依赖 `implementation(files(...))` 引入。`openssl.def` 里的硬编码路径实际上**不参与**这条构建路径，只有当有人想要重新生成这些 `.klib`（比如升级 OpenSSL 版本、新增 target）时才会用到它——而这条路径此前是彻底坏的，因为路径写死指向作者本机的 `/Users/davide/Desktop/...`。

已修复：
1. `openssl.def` 改为相对本仓库根目录的路径（`../openssl-apple/...`），不再硬编码个人路径。
2. 新增 `scripts/build-openssl-apple.sh`，用于在任意机器/CI 上重新构建 iOS/tvOS/watchOS/macOS 的 OpenSSL 1.1.1w，产物落在 `openssl.def` 期望的路径下。
3. `build-klibs.sh` 里的任务名是错的（`iosArm64Klib` 等不是真实 Gradle 任务名，正确的是 `iosArm64MainKlibrary`），已修正并补充 `jvmJar`（Android/JVM 制品）。
4. 新增 `.github/workflows/BuildKlibs.yml`，在每次 push/PR 时实际构建 iOS/macOS/tvOS/watchOS 全部 klib（macOS runner）以及 JVM(Android)/Linux/Windows 制品（ubuntu runner），把"这个仓库能否从源码构建出klib"变成一条持续验证的流水线，而不是只有 `DeployOnRelease.yml` 打包发布时才第一次尝试。

### 运行时结论（未改变，仍是已知上游限制）

第 20-53 行描述的运行时 `BIO_s_mem` 符号索引不匹配问题，根因是 Kotlin/Native 编译器本身的 cinterop 库身份识别缺陷（KT-78062），**不是**本仓库能通过修改 `openssl.def` 路径或 CI 脚本修复的问题——因为该 bug 发生在"消费方从 Maven Central 拉取已发布的二进制 klib 后，重新触发一次符号解析/链接"这一步，而不是本仓库自身构建阶段。

对于 RingoRTC App 这类消费方，目前唯一已验证有效的规避方式（ISSUE.md 原文第 55-63 行已经指出）是：**不要通过 Maven 坐标依赖已发布的 `kmqtt-client`/`kmqtt-common`，改用 Gradle composite build（`includeBuild("path/to/KMQTT")`）直接引入本仓库源码**，让 openssl cinterop 产物和最终 App 二进制在同一次编译会话、同一个符号索引空间里生成，从根本上避免"两份不同 cinterop 会话生成的 openssl 符号表"互相冲突。已发布到 Maven Central 的 iOS 预编译 klib（包括未来从本 fork 发布的版本）无法绕开这个上游编译器 bug。
