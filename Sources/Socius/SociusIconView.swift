import SwiftUI

/// Uses the app's own pixel artwork; rendered offline into AppIcon.icns.
struct SociusIconView: View {
    private let pet = PetModel()
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 200, style: .continuous)
                .fill(LinearGradient(colors: [Palette.cream, Color(red: 0.87, green: 0.89, blue: 0.80)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 200, style: .continuous)
                    .strokeBorder(.white.opacity(0.65), lineWidth: 5))
                .shadow(color: Palette.ink.opacity(0.16), radius: 14, y: 10)
            Ellipse().fill(Palette.ink.opacity(0.10))
                .frame(width: 420, height: 52).offset(y: 258).blur(radius: 14)
            CreatureView(model: pet, size: 840, idleMotion: false)
                .offset(y: -76)
        }.padding(64).frame(width: 1024, height: 1024)
    }
}
