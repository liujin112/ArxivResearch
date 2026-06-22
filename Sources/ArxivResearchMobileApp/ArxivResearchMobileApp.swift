#if os(iOS)
import SwiftUI
import ArxivResearchMobileUI

@main
struct ArxivResearchMobileApp: App {
    var body: some Scene {
        WindowGroup {
            MobileLibraryView()
        }
    }
}
#else
import Foundation

@main
enum ArxivResearchMobileApp {
    static func main() {
        print("ArxivResearchMobileApp is an iOS SwiftUI wrapper placeholder on this platform.")
    }
}
#endif
