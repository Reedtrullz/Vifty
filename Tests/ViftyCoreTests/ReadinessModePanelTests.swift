import SwiftUI
import XCTest
@testable import Vifty

@MainActor
final class ReadinessModePanelTests: XCTestCase {
    func testOnlyUserBindingWritesInvokeModeSelectionAction() {
        let state = ModeSelectionBindingState(selection: .fixed)
        let source = Binding<ModeSelection>(
            get: { state.selection },
            set: { state.selection = $0 }
        )
        var userSelections: [ModeSelection] = []
        let userBinding = ModeSelectionInteraction.userInitiatedBinding(
            selection: source,
            onUserSelection: { userSelections.append($0) }
        )

        source.wrappedValue = .auto
        XCTAssertEqual(state.selection, .auto)
        XCTAssertTrue(userSelections.isEmpty)

        userBinding.wrappedValue = .curve
        XCTAssertEqual(state.selection, .curve)
        XCTAssertEqual(userSelections, [.curve])
    }
}

@MainActor
private final class ModeSelectionBindingState {
    var selection: ModeSelection

    init(selection: ModeSelection) {
        self.selection = selection
    }
}
