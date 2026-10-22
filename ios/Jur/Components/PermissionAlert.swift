// When a permission was turned off: say what's off and offer the app's page in Settings.
// iOS shows its own prompt only once per permission, so after a "Don't Allow" this is the
// only way back.
import SwiftUI

extension View {
    func permissionAlert(isPresented: Binding<Bool>, title: String, message: String) -> some View {
        alert(title, isPresented: isPresented) {
            Button(t("perm.openSettings")) {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            Button(t("common.cancel"), role: .cancel) {}
        } message: {
            Text(message)
        }
    }
}
