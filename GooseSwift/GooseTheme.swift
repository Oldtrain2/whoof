import SwiftUI
import UIKit

enum WhoofTheme {
  static let deviceBackground = Color(red: 0.06, green: 0.09, blue: 0.11)

  // MARK: - Design tokens

  /// Continuous corner radius for cards. Unifies the metric cards (was 8pt, felt
  /// dated) with the larger SleepV2 panels for a coherent rounded language.
  static let cardRadius: CGFloat = 16

  /// Card fill. Dark mode is tinted toward the brand blue rather than a flat
  /// system gray, so cards read as part of the device-blue world, not generic.
  static let cardSurface = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.10, green: 0.13, blue: 0.16, alpha: 1)
      : .secondarySystemGroupedBackground
  })

  /// Hairline edge that lifts a card off the background without a hard border.
  static let cardHairline = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor.white.withAlphaComponent(0.08)
      : UIColor.black.withAlphaComponent(0.05)
  })

  /// Soft elevation. Diffuse and low-opacity, never a hard drop shadow.
  static let cardShadow = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor.black.withAlphaComponent(0.34)
      : UIColor(red: 0.06, green: 0.09, blue: 0.11, alpha: 0.08)
  })

  static let appBackground = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark ? deviceBackgroundUIColor : .systemGroupedBackground
  })

  static let plainBackground = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark ? deviceBackgroundUIColor : .systemBackground
  })

  static func configureAppearance() {
    UIWindow.appearance().backgroundColor = appBackgroundUIColor
    UITableView.appearance().backgroundColor = appBackgroundUIColor
    UICollectionView.appearance().backgroundColor = appBackgroundUIColor

    let navigationAppearance = UINavigationBarAppearance()
    navigationAppearance.configureWithTransparentBackground()
    navigationAppearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
    navigationAppearance.backgroundColor = navigationBarBackgroundUIColor
    navigationAppearance.shadowColor = .clear
    UINavigationBar.appearance().standardAppearance = navigationAppearance
    UINavigationBar.appearance().compactAppearance = navigationAppearance
    UINavigationBar.appearance().scrollEdgeAppearance = navigationAppearance

    let tabAppearance = UITabBarAppearance()
    tabAppearance.configureWithOpaqueBackground()
    tabAppearance.backgroundColor = appBackgroundUIColor
    tabAppearance.shadowColor = .clear
    UITabBar.appearance().standardAppearance = tabAppearance
    UITabBar.appearance().scrollEdgeAppearance = tabAppearance
  }

  private static let deviceBackgroundUIColor = UIColor(
    red: 0.06,
    green: 0.09,
    blue: 0.11,
    alpha: 1
  )

  private static let appBackgroundUIColor = UIColor { traits in
    traits.userInterfaceStyle == .dark ? deviceBackgroundUIColor : .systemGroupedBackground
  }

  private static let navigationBarBackgroundUIColor = UIColor { traits in
    let alpha: CGFloat = traits.userInterfaceStyle == .dark ? 0.58 : 0.46
    return appBackgroundUIColor.resolvedColor(with: traits).withAlphaComponent(alpha)
  }
}

extension View {
  func gooseScreenBackground() -> some View {
    background(WhoofTheme.appBackground.ignoresSafeArea())
  }

  func goosePlainBackground() -> some View {
    background(WhoofTheme.plainBackground.ignoresSafeArea())
  }

  func gooseListBackground() -> some View {
    scrollContentBackground(.hidden)
      .background(WhoofTheme.appBackground.ignoresSafeArea())
  }
}
