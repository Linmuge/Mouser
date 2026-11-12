import SwiftUI

struct ContentView: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        MouserWorkspaceView(model: model)
            .background {
                WindowAppearanceBridge(mode: model.appearanceMode)
            }
    }
}
