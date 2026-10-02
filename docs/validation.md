# v0.2.1 验证记录 / Validation

日期：2026-10-01。公开源码和下载包使用同一套生产实现；本次发布不改变产品接口或存储格式。

环境：Apple Silicon，macOS 26.4.1，Swift 6.2.4，完整Xcode；实际Codex CLI0.159.0。部署目标macOS14不等于所有系统版本都已实机验收。

## 本机结果

| 检查 | 结果与范围 |
| --- | --- |
| XCTest | 29项，0失败；Core17、连接9、Adapter3 |
| Release构建 | warnings-as-errors通过 |
| 原生多窗口 | 4窗口、复制、独立阅读、切会话、调整大小、覆盖面板、20次关闭释放通过 |
| 长历史 | 720项、31次远跳、最大显示更新15.36ms、最多27个已实现块；不是完整端到端延迟 |
| 状态恢复 | 会话、消息锚点、字体和几何恢复通过 |
| 后台刷新 | 原子替换、当时阅读位置、25次连点合并、缓存打开、独立取消、失败保留、首次渐进通过 |
| 外观/语言 | 浅深色、中英文、菜单、查找、复制、字号、隐藏恢复通过 |
| 首次引导 | 缺CLI、只读、模拟授权/撤销、无宿主/有宿主、不自动弹权限、仅完成一次通过 |
| 实际Codex | 同一条939项历史，20次完整读取＋20次刷新全部成功，无手动重试 |

真实读取中位数85ms，范围83–134ms；刷新中位数85ms，范围83–104ms。不含服务启动、查询列表、原生排版和显示。每轮禁用未固定缓存，确保请求真正访问服务。结果不是其他历史或电脑的延迟承诺。

原始记录：[live-results.txt](reliability/live-results.txt)。只导出耗时和条目数量，不含真实标题、ID或正文。

## 传输测试覆盖

真实子进程管道的中文/emoji响应超过5MiB，分片32,771字节；并发请求、通知、完整帧拼接、半帧EOF、最后响应后EOF、旧进程事件、共享启动/恢复、超时、三次上限、总时限、取消、迟到响应、拒绝/格式错误及非只读请求。

缓存和窗口测试区分部分进度与完整快照；失败不覆盖旧快照，取消一个读者不影响其他读者。细节见[可靠性说明](reliability/README.md)。重现命令见[贡献指南](../CONTRIBUTING.md)。

## 分发与隐私检查

- ZIP完整性、解压后严格临时签名、版本号、最低系统版本、arm64架构及可执行文件一致性检查。
- 公开目录采用明确文件清单，不包含本地Git历史、私人工作约定、内部设计记录、日志、状态或Codex历史。
- 六张图片逐张检查，全部为演示数据。单窗口按窗口ID捕获，多窗口由运行中的原生窗口视图捕获并排布；不使用桌面区域截图。
- GitHub CI执行源码单测、格式检查、release构建和解压签名检查；它不替代图形会话、真实Codex或系统权限验收。

## 尚未认证

没有Apple公证或干净机器Gatekeeper认证。没有完整真实宿主切换/最小化/恢复及所有全屏/Spaces组合的验收；引导的模拟权限撤销通过，不代表系统真实撤销完整认证。没有macOS14实机、Intel安装包或其他Agent的支持认证。超大单文本块和同步全文查找仍有性能边界。

## English

On 2026-10-01,29 XCTest cases passed (17 Core,9 connection,3 adapter), together with a warnings-as-errors release build and native regressions for multiple windows, recovery, refresh, themes/languages and setup. A720-item fixture made31 far jumps with a maximum display update of 15.36ms and 27 realized blocks; this is not end-to-end latency.

Codex CLI 0.159.0 on Apple Silicon/macOS 26.4.1 served 20 full reads and 20 refreshes of a 939-item history, without manual retries. Both medians were85ms; read range 83–134ms, refresh range 83–104ms. Startup, list queries and rendering are excluded. Unpinned cache capacity was zero each round. The linked raw record contains only timing/counts, not titles, IDs or bodies.

Tests cover fragmented Chinese/emoji responses over 5MiB, EOF ordering, disconnects, deadlines, shared reconnects, cancellation, late replies, malformed/rejected responses and read-only rejection. Native refresh tests cover atomic content replacement, live anchors, coalescing, cache opens, independent cancellation, failure preservation and cold progress.

Distribution checks cover ZIP integrity, strict extracted signature validation, version/deployment target, arm64 and executable equality. The public snapshot excludes local history and private/internal files. Six screenshots use synthetic data; single windows are captured by ID, while the multiwindow scene captures and arranges running native view trees without recording the desktop.

CI covers source tests, lint, release build and archive/signature checks, not graphical sessions, real Codex or OS authorization. Notarization, clean-machine Gatekeeper, full real host-following/permission revocation, all Spaces/full-screen combinations, macOS 14 hardware, Intel binaries and other providers remain unverified. Huge individual blocks and synchronous full-history Find remain performance boundaries.
