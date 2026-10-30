# NeoFreeBird 操作栏媒体下载快捷键

本项目是一个独立的配套动态库 `NFBActionBarDownload.dylib`。它调用现有 NeoFreeBird 的下载模块，在帖子底部的书签左侧增加下载按钮；不包含 X 安装包，也不替换 NeoFreeBird 的主动态库。

目标组合：**NeoFreeBird 7.3.0 + X 12.38.1 + iOS 17.2.1，arm64 真机**。当前版本为**启动防护候选版 2，增加空载对照库，尚未完成真机验证**。

旧版源码在[用户仓库的 Actions](https://github.com/eileenluooo-beep/NeoFreeBird_lx/actions/runs/41013106834) 编译成功，但用户反馈启用后点开 X 立即闪退，禁用后恢复。构建成功只证明编译和产物检查通过。当前没有取得崩溃日志，尚不能确定根因。

本次修补移除了动态库加载回调内的宿主初始化，将安装安排到主队列；检查方法时只遍历已注册父类的方法列表，避免在未注册子类上查询缺失方法而触发运行时解析。新增 macOS 运行时回归检查会由 Actions 执行，覆盖接口缺失、类未初始化、子类注册与废弃；该检查不运行 X 或 UIKit，不能替代手机验收。当前 Windows 环境没有 Xcode，本候选版尚未编译或注入验证。

## 行为

- 含视频或 GIF、且 NeoFreeBird 的“下载媒体”开关开启时，显示原生下载图标。
- 位置优先为书签之前；书签被隐藏时放到分享之前。由 X 的原生操作栏重新排列，不覆盖按钮或使用固定屏幕坐标。
- 点击后调用原 `DownloadInlineButton` 的下载选项，保留清晰度、多个视频、保存方式和进度行为。
- 点击时读取按钮当前的 view model，不把旧帖子的媒体捕获在闭包里。
- 纯文字/纯图片帖子不新增按钮：本次复用的 NeoFreeBird 下载器处理视频和 GIF。
- 保留原“更多”菜单入口以及回复、转发、点赞、浏览量、书签、分享行为。
- 依赖原插件提供的类和方法；按钮注册检查发现接口缺失时不安装快捷键，输出不含用户内容的状态日志。这项检查不能保证捕获宿主内部的所有兼容问题。
- 使用 Objective-C runtime 连接原生按钮，不附带 Substrate、ElleKit 或其他 Hook 框架。

## 在 GitHub 构建

1. 将源码 ZIP **解压后的内容**上传到仓库根目录，覆盖旧版文件。必须同时包含 `NFBMethodLookup.h`、`test-runtime.sh`、`tests/runtime-smoke.m` 和 `.github/workflows/build-shortcut.yml`；不要只上传 ZIP。
2. 提交到默认分支，然后打开 **Actions → Build download shortcut dylib → Run workflow**。
3. 成功后会有两个产物：**NFBActionBarLoadProbe-arm64**（空载对照）和 **NFBActionBarDownload-arm64**（快捷键候选版）。先下载前者。
4. 每个产物包含对应动态库、SHA-256、构建模式、系统依赖、源码提交和 Xcode 版本记录。

这个流程不要求 X 的 IPA，不需要上传 Apple ID、证书或私钥。它只构建动态库并上传本次运行产物，不创建 Release。产物经过临时签名；最终注入/安装仍由你的注入器或签名工具按实际设备要求处理。

## 没有崩溃日志时的对照步骤

1. 保持导致闪退的旧快捷键库禁用，确认 X 能打开；保留原 NeoFreeBird 及其依赖。
2. 解压 **NFBActionBarLoadProbe-arm64**，只添加里面的 `NFBActionBarLoadProbe.dylib`，使用同一注入器和相同注入方式。确认测试库已启用，旧快捷键库仍禁用；此时不要加入快捷键候选版。
3. 完全退出并重新打开 X，记录是否仍然点开就退出。空载版没有按钮，预期界面与未添加快捷键时相同。
4. 若空载版仍导致退出，优先核对注入/签名流程、依赖和加载结果；若空载版能打开且确认实际已加载，则下一步检查快捷键的宿主接口和按钮代码。单次不闪退不能证明库实际加载，未取得日志前也不能把对照结果当作最终根因。
5. 完成对照后禁用或移除空载库。需要验证快捷键候选版时，只添加 **NFBActionBarDownload-arm64** 中的 `NFBActionBarDownload.dylib`，不要同时启用多份旧/新快捷键库。

两个库由同一份源码和相同目标平台/编译/签名选项构建。空载版使用 `NFB_LOAD_ONLY=1`，加载回调直接返回，不排队执行、不查询 X 的类、不构造按钮、不修改方法；快捷键版使用 `NFB_LOAD_ONLY=0`。构建会比较两者链接的系统库并在不一致时停止。这些检查不模拟白魔注入器或真实手机签名环境。

本轮未操作白魔注入器，具体按钮名称和签名步骤请以你的版本为准。先确认 NeoFreeBird 设置中的下载媒体开关已打开，再在含视频/GIF 的帖子上检查下载图标。源代码 ZIP 不是可注入文件。

## 本机 Mac 构建

安装 Xcode 及 iPhoneOS SDK 后，在本目录执行：

```bash
bash test-runtime.sh
bash build.sh
```

输出：`build/load-test/NFBActionBarLoadProbe.dylib` 和 `build/shortcut/NFBActionBarDownload.dylib`。构建开启 `-Wall -Wextra -Werror`，失败会停止；检查签名、arm64 和 iOS 平台信息后生成 SHA-256。两者最低部署版本均为 iOS 15；仅有部署版本匹配不代表全部运行时接口兼容。原生 UIKit 按钮本身仍须在目标设备上验收。

## 验证边界

Windows 本轮可检查源码差异、Bash/YAML 语法、交付 ZIP 内容和 SHA-256；这些检查不能替代本候选版的 Objective-C 编译、macOS 运行时回归检查或 UI 验收。随包 `VALIDATION.json` 记录实际执行结果。

仍待调查：宿主私有方法是否与接口记录一致、原生基类是否支持来自早期自定义按钮的动作编号 131，以及注入器是否成功加载并签名本库。用户反馈未找到当天的分析日志，因此本版增加空载对照，不要求等待日志才能继续排查。后续如出现崩溃报告，请保留 Termination Reason、Exception Type、Last Exception Backtrace 和触发线程。没有进一步证据前不能把本次防护改动视为已确认修复。

待目标设备验证：正常视频、GIF、多个视频、文字/图片帖子、关闭下载开关、快速滚动复用、帖子详情、隐藏书签、深浅色、动态字体、旋转及原有按钮交互。本轮没有上述场景的通过证据。

## 接口依据与许可

- [NeoFreeBird 7.3.0 下载入口](https://github.com/NeoFreeBird/app/blob/v7.3.0/src/Hooks/MediaDownloads.x)：设置键、视频/GIF 类型和下载器调用。
- [当前操作栏类接口](https://github.com/NeoFreeBird/app/blob/v7.3.0/src/Hooks/HideUI.x)：按钮类数组及书签/浏览量/分享类。
- [作者维护的原生按钮接口记录](https://github.com/NeoFreeBird/classdump/blob/72524d49d12bfa18278df85a995e1f9d65afa493/TwitterSPMAppMigration/TTAStatusInlineActionButton.h)：初始化、图片、状态、布局和点击接口；记录本身不能证明所有新版运行时都相同。
- [早期内联按钮](https://github.com/NeoFreeBird/tweak/blob/master/BHDownloadInlineButton.m)：原自定义下载动作编号。
- [Apple Objective-C runtime 实现](https://github.com/apple-oss-distributions/objc4/blob/main/runtime/objc-runtime-new.mm)：`class_getInstanceMethod` 可能尝试方法解析；元类关联查找失败会中止进程。

这是用户定制的配套项目，不是 NeoFreeBird 官方发布版本。沿用 GPL-3.0 许可，见 `LICENSE`。
