# 安装与首次授权

完整包里已有Mirror.app与skills。请保持文件夹完整，交给本机Agent读取README并执行setup.sh；安装后按宿主约定注册两项技能，部分宿主需重开会话。普通用户也可直接将Mirror.app拖到应用程序打开。

小技能包缺少桌面端时，Agent按mirror-setup执行install-preview.sh，下载固定GitHub ZIP并校验SHA256、应用标识、版本、构建号、签名和CDHash；安装到用户Applications。不要求你编译、复制命令或填写API Key。

当前是未Apple公证的测试版。macOS首次打开若拦截，请先核对项目与版本，仅在你决定信任该软件时亲手处理系统提示。参考[Apple说明](https://support.apple.com/en-us/102445)。不删quarantine、不关闭Gatekeeper、不绕过管理员限制。

打开后选择本机Codex可执行文件；不是登录新账号，也不是选择一个聊天窗口。先只读使用无需辅助功能。需要跟随Codex窗口时，在系统设置→隐私与安全性→辅助功能中授权Mirror，再绑定目标窗口。绑定对象是宿主窗口，不是其中的某个聊天标签。

遇到其他版本不自动覆盖；Agent先说明现有应用，得到替换确认后备份再安装。退出由你正常完成，不强制结束进程。manual_open_required表示已安装、等待你首次确认，不代表内容已读取。

断网、下载失败、校验失败时停止，不换未经验证的下载。函数调用先读status的revision；出现人工冲突或暂停不强制继续。
