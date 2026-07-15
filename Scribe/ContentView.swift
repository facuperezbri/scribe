import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: DictationViewModel

    var body: some View {
        ScribeMainView(viewModel: viewModel)
    }
}

#Preview {
    ContentView(viewModel: DictationViewModel())
}
