import SwiftUI
import UIKit

struct KeyboardSetupView: View {
    var body: some View {
        List {
            Section {
                KeyboardSetupSteps()
            } footer: {
                Text("「完整取用」讓鍵盤能與這部裝置上的 KVoice App 溝通（接收你的聽寫內容並讀取你的模式）。KVoice 看不到你用其他鍵盤輸入的內容，KVoice 鍵盤也不會把任何資料傳出裝置。")
            }
            Section {
                OpenSettingsButton()
            }
            Section("運作方式") {
                Text("iOS 鍵盤無法使用麥克風。當你點 KVoice 鍵盤上的麥克風時，KVoice 會開啟並開始聆聽，你再滑回原本的 App。文字會輸入在你剛剛離開的地方。之後幾分鐘內，鍵盤不用切換 App 就能開始和停止聽寫。")
                    .font(.callout)
            }
        }
        .navigationTitle("鍵盤")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct KeyboardSetupSteps: View {
    static let steps: [(String, String)] = [
        ("gearshape", "開啟「設定」App"),
        ("switch.2", "前往「一般」›「鍵盤」›「鍵盤」"),
        ("plus.circle", "點「加入新鍵盤…」並選擇 KVoice"),
        ("lock.open", "點 KVoice，並開啟「允許完整取用」"),
        ("globe", "在任何 App 裡，按住地球鍵即可切換到 KVoice")
    ]

    var body: some View {
        ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
            HStack(spacing: 14) {
                Text("\(index + 1)")
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.accentColor, in: .circle)
                Label(step.1, systemImage: step.0)
            }
        }
    }
}

struct OpenSettingsButton: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button("開啟設定", systemImage: "arrow.up.forward.app") {
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        }
    }
}
