import FirebaseCore
import GoogleSignIn
import SwiftUI

final class AppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    FirebaseApp.configure()

    if let clientID = FirebaseApp.app()?.options.clientID {
      GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
    }

    return true
  }
}

@main
struct MagonoteApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @State private var session = SessionStore()

  var body: some Scene {
    WindowGroup {
      Group {
        if session.isSignedIn {
          NavigationStack {
            DocumentListView(client: APIClientFactory.makeClient())
          }
        } else {
          LoginView()
        }
      }
      .environment(session)
      .task {
        session.start()
      }
      .onOpenURL { url in
        GIDSignIn.sharedInstance.handle(url)
      }
    }
  }
}
