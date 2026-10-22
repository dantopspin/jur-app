// The widget extension: for now, only the departure Live Activity.
import SwiftUI
import WidgetKit

@main
struct JurWidgetsBundle: WidgetBundle {
    var body: some Widget {
        DepartureLiveActivity()
    }
}
