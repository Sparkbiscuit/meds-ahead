import SwiftUI
import WidgetKit

@main
struct MedsWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NextDoseWidget()
        RunsOutWidget()
    }
}
