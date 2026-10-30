# NeoFreeBird 操作栏媒体下载快捷键

本项目是一个独立的配套动态库 `NFBActionBarDownload.dylib`。它调用现有 NeoFreeBird 的下载模块，在帖子底部的书签左侧增加下载按钮；不包含 X 安装包，也不替换 NeoFreeBird 的主动态库。

目标组合：**NeoFreeBird 7.3.0 + X 12.38.1，iOS arm64 真机**。这是源码适配目标，不是已取得的真机兼容结论。当前执行电脑为 Windows，本轮没有编译成功的 `.dylib`，也没有设备截图或交互验收记录。

## 行为

- 含视频或 GIF、且 NeoFreeBird 的“下载媒体”开关开启时，显示原生下载图标。
- 位置优先为书签之前；书签被隐藏时放到分享之前。由 X 的原生操作栏重新排列，不覆盖按钮或使用固定屏幕坐标。
- 点击后调用原 `DownloadInlineButton` 的下载选项，保留清晰度、多个视频、保存方式和进度行为。
- 点击时读取按钮当前的 view model，不把旧帖子的媒体捕获在闭包里。
- 纯文字/纯图片帖子不新增按钮：本次复用的 NeoFreeBird 下载器处理视频和 GIF。
- 保留原“更多”菜单入口以及回复、转发、点赞、浏览量、书签、分享行为。
- 依赖原插件提供的类和方法；接口缺失时不安装快捷键，输出不含用户内容的状态日志。
- 使用 Objective-C runtime 连接原生按钮，不附带 Substrate、ElleKit 或其他 Hook 框架。

## 在 GitHub 构建

1. 新建一个空 GitHub 仓库，将源码 ZIP **解压后的内容**上传到仓库根目录。必须包含 `.github/workflows/build-shortcut.yml`；不要只上传 ZIP。
2. 提交到默认分支，然后打开 **Actions → Build download shortcut dylib → Run workflow**。
3. 成功后下载 **Artifacts → NFBActionBarDownload-arm64**。
4. 解压产物，取出 `NFBActionBarDownload.dylib`。里面另有 SHA-256、源码提交和 Xcode 版本记录。

这个流程不要求 X 的 IPA，不需要上传 Apple ID、证书或私钥。它只构建动态库并上传本次运行产物，不创建 Release。产物经过临时签名；最终注入/安装仍由你的注入器或签名工具按实际设备要求处理。

## 在已有 NeoFreeBird 的 X 中使用

保留原 NeoFreeBird 及其依赖，把本次生成的 `NFBActionBarDownload.dylib` 作为**额外插件**加入同一个 X。不要把它当作 NeoFreeBird 主插件，也不要重复加载两个 NeoFreeBird 主库。通过你正在使用的注入器完成处理后，完全退出并重新打开 X。

本轮未操作白魔注入器，具体按钮名称和签名步骤请以你的版本为准。先确认 NeoFreeBird 设置中的下载媒体开关已打开，再在含视频/GIF 的帖子上检查下载图标。源代码 ZIP 不是可注入文件。

## 本机 Mac 构建

安装 Xcode 及 iPhoneOS SDK 后，在本目录执行：

```bash
bash build.sh
```

输出：`build/NFBActionBarDownload.dylib`。构建开启 `-Wall -Wextra -Werror`，失败会停止；检查签名、arm64 和 iOS 平台信息后生成 SHA-256。原生 UIKit 按钮本身仍须在目标设备上验收。

## 验证边界

Windows 本轮可检查源码差异、Bash/YAML 语法、交付 ZIP 内容和 SHA-256；这些检查不能替代 Objective-C 编译、运行时接口验证或 UI 验收。随包 `VALIDATION.json` 记录实际执行结果。

待目标设备验证：正常视频、GIF、多个视频、文字/图片帖子、关闭下载开关、快速滚动复用、帖子详情、隐藏书签、深浅色、动态字体、旋转及原有按钮交互。本轮没有上述场景的通过证据。

## 接口依据与许可

- [NeoFreeBird 7.3.0 下载入口](https://github.com/NeoFreeBird/app/blob/v7.3.0/src/Hooks/MediaDownloads.x)：设置键、视频/GIF 类型和下载器调用。
- [当前操作栏类接口](https://github.com/NeoFreeBird/app/blob/v7.3.0/src/Hooks/HideUI.x)：按钮类数组及书签/浏览量/分享类。
- [作者维护的原生按钮接口记录](https://github.com/NeoFreeBird/classdump/blob/72524d49d12bfa18278df85a995e1f9d65afa493/TwitterSPMAppMigration/TTAStatusInlineActionButton.h)：初始化、图片、状态、布局和点击接口；记录本身不能证明所有新版运行时都相同。
- [早期内联按钮](https://github.com/NeoFreeBird/tweak/blob/master/BHDownloadInlineButton.m)：原自定义下载动作编号。

这是用户定制的配套项目，不是 NeoFreeBird 官方发布版本。沿用 GPL-3.0 许可，见 `LICENSE`。
