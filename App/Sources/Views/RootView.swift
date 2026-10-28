import KVoiceKit
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppPreferences.onboardingDoneKey, store: AppPreferences.store) private var onboardingDone = false

    var body: some View {
        @Bindable var model = model
        @Bindable var handoff = model.handoff
        TabView(selection: $model.selectedTab) {
            Tab("聽寫", systemImage: "waveform", value: AppTab.home) {
                HomeView()
            }
            Tab("模式", systemImage: "square.stack.3d.up", value: AppTab.modes) {
                ModesView()
            }
            Tab("歷史紀錄", systemImage: "clock.arrow.circlepath", value: AppTab.history) {
                HistoryView()
            }
            Tab("設定", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .fullScreenCover(isPresented: $handoff.isPresentingRecorder) {
            HandoffRecordingView()
        }
        .fullScreenCover(isPresented: Binding(
            get: { !onboardingDone && !AppPreferences.skipsOnboarding && !handoff.isPresentingRecorder },
            set: { if !$0 { onboardingDone = true } }
        )) {
            OnboardingView { onboardingDone = true }
        }
    }
}
