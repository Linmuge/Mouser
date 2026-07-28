import SwiftUI

struct ContentView: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        PrecisionWorkspaceView(model: model)
            .background {
                WindowAppearanceBridge(mode: model.appearanceMode)
            }
    }
}
