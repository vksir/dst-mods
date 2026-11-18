-- Snappy Actions（跟手动作）
-- 纯客户端 mod：让"按空格捡东西"立即开始且平滑收尾，提前解除 0.5 秒重复冷却。
--
-- modinfo 沙箱没有任何标准库（docs/dst-modding-pitfalls.md §2）：
-- 本文件只允许字符串/数字常量、表构造器与字符串元表调用。

name = "Snappy Actions (跟手动作)"

description = [[按下空格捡东西不再"弯腰僵住"：

动作立即开始（客户端预测），在预测的服务端执行时刻本地补播起身动画（pickup_pst）平滑收尾，
并提前解除游戏写死的 0.5 秒重复冷却——单击更利索、连捡不断节奏。

两档可调：
· 保守：按实测基线收尾（≈原版确认时刻，但不依赖快照准时）
· 激进：把等待钳制在"零延迟理想网络"物理下限（高 ping 收益明显）

带验证与回滚：服务端迟迟没做，就把藏起来的物品放回来并暂时退回原版行为。
草/树枝等长动作同样享受提前解除冷却与平滑起身，但不做物品隐藏。

纯客户端，任何服务器可用，其他人无需安装。
与 Better Lag Compensation 功能重叠，二选一（检测到 BLC 时本 mod 自动让位）。]]

author = "dst-mods"
version = "0.1.1"

api_version = 10
dst_compatible = true
dont_starve_compatible = false
reign_of_giants_compatible = false
client_only_mod = true
all_clients_require_mod = false
server_filter_tags = {}

configuration_options =
{
    {
        name = "mode",
        label = "收尾时机",
        hover = "保守=按实测基线（约等于原版确认时刻，但不等快照）；激进=钳制在零延迟物理下限（约 233ms，高 ping 才有感）；关闭=本 mod 不介入",
        options =
        {
            { description = "保守", data = "conservative" },
            { description = "激进", data = "aggressive" },
            { description = "关闭", data = "off" },
        },
        default = "conservative",
    },
    {
        name = "margin",
        label = "安全余量",
        hover = "收尾与连拍调度额外加的帧数。网络抖动大就加 1 帧；越大越稳、越慢一点",
        options =
        {
            { description = "0 帧", data = 0 },
            { description = "1 帧（默认）", data = 1 },
            { description = "2 帧", data = 2 },
            { description = "3 帧", data = 3 },
        },
        default = 1,
    },
    {
        name = "repeat_cd",
        label = "按住连拍间隔",
        hover = "按住空格连续捡拾的最小间隔。原版 0.5s：不会多捡；快速 0.35s：扫场明显更快，但按住稍长就会多捡下一个（配合 LeftClick 链式发送）",
        options =
        {
            { description = "原版 0.5s（默认）", data = 0.5 },
            { description = "快速 0.35s", data = 0.35 },
            { description = "稳 0.65s", data = 0.65 },
        },
        default = 0.5,
    },
    {
        name = "lab",
        label = "日志",
        hover = "在 client_log.txt 输出：回滚/退避等异常与每分钟小结",
        options =
        {
            { description = "开", data = true },
            { description = "关", data = false },
        },
        default = true,
    },
    {
        name = "key",
        label = "开关热键",
        hover = "游戏中临时开/关本 mod，用来与原版手感对比",
        options =
        {
            { description = "无", data = false },
            { description = "F8", data = "KEY_F8" },
            { description = "F9", data = "KEY_F9" },
            { description = "F10", data = "KEY_F10" },
            { description = "F11", data = "KEY_F11" },
            { description = "F12", data = "KEY_F12" },
        },
        default = false,
    },
}
