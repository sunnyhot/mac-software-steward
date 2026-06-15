import Foundation

@main
struct SparkleAppcastCheckerTest {
    static func main() {
        let appcast = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>
            <item>
              <title>Version 2.0</title>
              <enclosure sparkle:shortVersionString="2.0" sparkle:version="200" url="https://example.com/app.zip" />
            </item>
          </channel>
        </rss>
        """

        let parsed = SparkleAppcastChecker.parseLatestVersion(from: Data(appcast.utf8))
        precondition(parsed == "2.0")

        let fallback = """
        <rss><channel><item><sparkle:version>3.1</sparkle:version></item></channel></rss>
        """
        precondition(SparkleAppcastChecker.parseLatestVersion(from: Data(fallback.utf8)) == "3.1")
        precondition(SparkleAppcastChecker.isNewerVersion("2.0", than: "1.9"))
        precondition(!SparkleAppcastChecker.isNewerVersion("1.0", than: "1.0"))
    }
}
