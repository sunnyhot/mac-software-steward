import Foundation

@main
struct PackageProgressParserTest {
    static func main() {
        let fetching = PackageProgressParser.parse(stream: "stdout", text: "==> Fetching downloads for: iina")
        precondition(fetching.phaseText == "准备下载", "Expected 准备下载, got \(String(describing: fetching.phaseText))")
        precondition(fetching.detail == "准备下载 iina", "Unexpected detail: \(fetching.detail)")
        precondition(fetching.downloadFraction == 0)

        let downloading = PackageProgressParser.parse(stream: "stdout", text: "==> Downloading https://example.com/IINA.dmg")
        precondition(downloading.phaseText == "下载中")
        precondition(downloading.downloadFraction == 0)

        let curl = PackageProgressParser.parse(
            stream: "stderr",
            text: " 45  185M   45  83.2M    0     0  10.4M      0  0:00:17  0:00:08  0:00:09 10.6M"
        )
        precondition(curl.phaseText == "下载中")
        precondition(abs((curl.downloadFraction ?? 0) - 0.45) < 0.001, "Expected 45%, got \(String(describing: curl.downloadFraction))")
        precondition(curl.downloadSizeText == "83.2M / 185M", "Unexpected size text: \(String(describing: curl.downloadSizeText))")
        precondition(curl.downloadSpeedText == "10.6M/s", "Unexpected speed text: \(String(describing: curl.downloadSpeedText))")

        let installing = PackageProgressParser.parse(stream: "stdout", text: "==> Installing App 'IINA.app' to '/Applications/IINA.app'")
        precondition(installing.phaseText == "安装中")
        precondition(installing.detail == "安装中 IINA.app", "Unexpected install detail: \(installing.detail)")
        precondition(installing.clearsDownloadProgress)

        let cleanup = PackageProgressParser.parse(stream: "stdout", text: "==> Purging files for version 1.4.3 of Cask iina")
        precondition(cleanup.phaseText == "清理中")
        precondition(cleanup.clearsDownloadProgress)

        let command = PackageProgressParser.parse(stream: "command", text: "$ brew upgrade --cask --greedy iina")
        precondition(command.phaseText == "执行命令")
        precondition(command.detail == "brew upgrade --cask --greedy iina")
    }
}
