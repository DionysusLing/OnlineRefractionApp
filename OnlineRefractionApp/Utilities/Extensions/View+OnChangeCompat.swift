import SwiftUI

extension View {
    @ViewBuilder
    func onChangeCompat<T: Equatable>(
        _ value: T,
        _ action: @escaping (_ oldValue: T, _ newValue: T) -> Void
    ) -> some View {
        if #available(iOS 17.0, *) {
            self.onChange(of: value, { old, new in
                action(old, new)
            })
        } else {
            self.onChange(of: value, perform: { new in
                action(value, new)
            })
        }
    }
}
