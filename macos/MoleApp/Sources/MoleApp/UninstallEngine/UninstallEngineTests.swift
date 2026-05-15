import Foundation

// MARK: - Basic Functionality Tests
actor UninstallEngineTests {

    let engine = UninstallEngine()

    /// Test basic scanning functionality
    func testBasicScanning() async throws {
        print("Testing basic scanning functionality...")

        do {
            let apps = try await engine.scanApplications()
            print("✓ Successfully scanned \(apps.count) applications")

            if !apps.isEmpty {
                let firstApp = apps[0]
                print("✓ Sample app: \(firstApp.name) (\(firstApp.id))")
                print("  - Path: \(firstApp.path.path)")
                print("  - Size: \(ByteFormat.string(firstApp.size))")
                print("  - Version: \(firstApp.version)")
            }
        } catch {
            print("✗ Scanning failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Test application listing
    func testApplicationListing() async throws {
        print("\nTesting application listing...")

        do {
            let apps = try await engine.listApps()
            print("✓ Successfully listed \(apps.count) applications")
        } catch {
            print("✗ Listing failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// test search functionality
    func testApplicationSearch() async throws {
        print("\nTesting application search...")

        do {
            let apps = try await engine.searchApps(byName: "Safari")
            print("✓ Found \(apps.count) apps matching 'Safari'")
        } catch {
            print("✗ Search failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Test metadata cache
    func testMetadataCache() async throws {
        print("\nTesting metadata cache...")

        do {
            if let cache = await engine.getMetadataFromCache() {
                print("✓ Cache loaded with \(cache.apps.count) entries")
                print("  - Cache timestamp: \(cache.timestamp)")
                print("  - Expired: \(cache.isExpired)")
            } else {
                print("✓ No cache found (this is expected for first run)")
            }
        } catch {
            print("✗ Cache test failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Test application statistics
    func testApplicationStatistics() async throws {
        print("\nTesting application statistics...")

        do {
            let stats = try await engine.getApplicationStats()
            print("✓ Application statistics:")
            print("  - Total apps: \(stats.totalApps)")
            print("  - Homebrew casks: \(stats.brewCaskApps)")
            print("  - System apps: \(stats.systemApps)")
            print("  - Background apps: \(stats.backgroundApps)")
            print("  - Recent apps: \(stats.recentApps)")
            print("  - Total size: \(String(format: "%.2f", stats.totalSizeGB)) GB")
        } catch {
            print("✗ Statistics failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Test residual file scanning
    func testResidualScanning() async throws {
        print("\nTesting residual file scanning...")

        do {
            // Use a common bundle ID for testing
            let residuals = try await engine.findResidualFiles(
                bundleId: "com.apple.Safari",
                appName: "Safari"
            )
            print("✓ Found \(residuals.count) residual files for Safari")
        } catch {
            print("✗ Residual scanning failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Run all tests
    func runAllTests() async {
        print("=== UninstallEngine Basic Functionality Tests ===\n")

        var passed = 0
        var failed = 0

        // Test basic scanning
        do {
            try await testBasicScanning()
            passed += 1
        } catch {
            failed += 1
        }

        // Test application listing
        do {
            try await testApplicationListing()
            passed += 1
        } catch {
            failed += 1
        }

        // Test search functionality
        do {
            try await testApplicationSearch()
            passed += 1
        } catch {
            failed += 1
        }

        // Test metadata cache
        do {
            try await testMetadataCache()
            passed += 1
        } catch {
            failed += 1
        }

        // Test application statistics
        do {
            try await testApplicationStatistics()
            passed += 1
        } catch {
            failed += 1
        }

        // Test residual scanning
        do {
            try await testResidualScanning()
            passed += 1
        } catch {
            failed += 1
        }

        print("\n=== Test Results ===")
        print("Passed: \(passed)")
        print("Failed: \(failed)")
        print("Total: \(passed + failed)")
    }
}

// MARK: - Test Runner
@main
struct TestRunner {
    static func main() async {
        let tests = UninstallEngineTests()
        await tests.runAllTests()
    }
}