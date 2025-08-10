import SwiftUI

struct PrimaryButton: View {
    var title: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.headline).foregroundColor(AppColor.accent)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(AppColor.chip).clipShape(Capsule())
        }
        .padding(.horizontal, 20)
    }
}

struct VoiceBar: View {
    var body: some View {
        Image(Asset.voice)
            .resizable()
            .scaledToFit()
            .frame(height: 66)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

extension View {
    func pagePadding() -> some View { padding(.horizontal, 20).padding(.top, 16) }
}


import SwiftUI
import UIKit

struct SafeImage: View {
    let name: String
    let size: CGSize?

    init(_ name: String, size: CGSize? = nil) {
        self.name = name
        self.size = size
    }

    var body: some View {
        if UIImage(named: name) != nil {
            Image(name)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size?.width, height: size?.height)
        } else {
            Image(systemName: "exclamationmark.triangle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size?.width ?? 28, height: size?.height ?? 28)
                .foregroundColor(.orange)
                .onAppear {
                    #if DEBUG
                    NSLog("⚠️ Missing asset: \(name)")
                    #endif
                }
        }
    }
}

