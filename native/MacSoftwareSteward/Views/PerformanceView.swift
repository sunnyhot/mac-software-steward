import SwiftUI

struct PerformanceView: View {
    var body: some View {
        EmptyStateView(
            symbol: "speedometer",
            title: "暂无性能记录",
            text: "完成一次扫描后，这里会显示阶段耗时、最近趋势和瓶颈提示。"
        )
    }
}
