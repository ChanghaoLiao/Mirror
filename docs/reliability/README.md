# Mirror 0.2.1 读取与刷新验收

日期：2026-10-01。范围：本项目的 Codex 只读连接、刷新交互、内存快照；保留现有 provider 接口和窗口状态存储格式。

## 结果

实际本机 Codex CLI 0.159.0：同一条 939 项的历史，连续 20 次完整读取和 20 次刷新均成功，无需手动重试。读取/刷新中位数均为 85ms，范围分别 83–134ms、83–104ms。每轮使用零容量未固定缓存，确保真的发起历史读取，未以缓存命中充当服务成功。原始元数据：[live-results.txt](live-results.txt)。时间不含启动/查询列表、原生排版和显示，不是所有历史的延迟保证。本次不导出真实标题、ID 或正文。

29 项 XCTest、release warnings-as-errors 构建、严格格式检查和 diff 空白检查通过。`--verify-refresh`、`--verify-ui`、`--verify-recovery`、`--verify-ocean`、`--verify-setup` 原生回归通过。

## 修复

之前 FileHandle 回调对每块数据创建独立 Task，可能改变大响应的数据顺序；进程退出回调也可能抢在最后一块响应处理之前断开连接。现在读取与入队在同一锁内，单一消费者按顺序拼接完整 JSONL；大响应只搜索新到的区域，EOF 在已入队数据之后处理，旧连接事件由 generation 隔离。完整格式异常明确报错；中途 EOF，包括尚未完成的消息，按可恢复断连处理。

每个只读 RPC 最多三次尝试，重试间隔 250/750ms；单次请求 15 秒、握手 8 秒、总预算 45 秒。整个对话（含分页）另设 45 秒预算，取消会立即解除调用方的等待。断连/超时才重新建立服务，拒绝/格式错误不重试。并发调用共享启动和恢复，显式退出连接后不再自动启动。取消一个调用只清理它的等待，其他读者继续。

刷新中保留旧快照；只在完整成功后替换。失败/取消保留内容，提交时读取当前锚点，避免跳回刚按刷新的位置。同一窗口连点刷新合并，多窗口同源更新共享请求；已有缓存可立即打开新窗口，后台更新完成后同步快照。首次无缓存读取仍渐进显示。查找面板、匹配列表和清除返回的位置在刷新后继续可用。

## 验证场景

- 实际子进程管道：大于 5MiB 的中文/emoji 响应，32,771 字节分片、通知与并发请求，验证内容首尾、长度、请求身份和单进程共享。
- 断连、半条消息 EOF、超时，自动恢复；并发失败共享重连；最多三次和总时限；格式错误/拒绝/非只读调用不重试。
- 握手期间取消、迟到响应、响应后立刻 EOF、退出停止重试；等待与计时任务清理。
- 缓存刷新共享、失败不替换缓存也不通知完整成功；取消一个订阅不影响其他订阅。
- 原生窗口：连续 25 次刷新点击合并；部分结果不覆盖已有内容；刷新期间滚动位置保留；失败、取消、缓存立即打开、兄弟窗口更新，以及首次渐进读取。
- 原有多窗口、查找、复制、语言/外观、关闭释放、恢复与首次权限引导继续通过。720 项长历史回归最大显示跳转 15.36ms，最多 27 个已实现块。

## 重现

```sh
bash scripts/swift.sh test -Xswiftc -warnings-as-errors
bash scripts/build.sh
MIRROR_PREFS_SUITE=local.mirror.reliability.verify MIRROR_STATE_PATH="$PWD/.build/reliability-live.json" dist/Mirror.app/Contents/MacOS/Mirror --verify-reliability
MIRROR_PREFS_SUITE=local.mirror.reliability.verify MIRROR_STATE_PATH="$PWD/.build/reliability-refresh.json" dist/Mirror.app/Contents/MacOS/Mirror --verify-refresh
```

管道故障测试的 Python 仅为开发用子进程夹具，不是产品运行依赖。生产仍通过本机 Codex 的 App Server 只读获取历史，没有模型调用、写对话、遥测或新增磁盘正文缓存。正式签名/公证、真实宿主切换与权限撤销仍是独立平台验收；本次重新构建更换临时签名后，macOS 可能要求重新授权窗口跟随。
