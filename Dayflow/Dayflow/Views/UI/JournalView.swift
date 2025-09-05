import SwiftUI

struct JournalView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Journal")
                .font(.custom("InstrumentSerif-Regular", size: 42))
                .foregroundColor(.primary)
                .padding(.leading, 10) // Match Timeline header inset

            Text("Journal coming soon")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
