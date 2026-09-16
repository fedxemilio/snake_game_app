import SwiftUI
import SpriteKit

struct ContentView: View {
    private let scene: SKScene = {
        let scene = GameScene()
        scene.scaleMode = .resizeFill
        return scene
    }()

    var body: some View {
        SpriteView(scene: scene)
            .ignoresSafeArea()
            .statusBarHidden()
    }
}

#Preview {
    ContentView()
}
