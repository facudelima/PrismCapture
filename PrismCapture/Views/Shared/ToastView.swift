import SwiftUI

struct ToastBanner: View {
    let message: String
    var body: some View { ToastView(message: message) }
}
