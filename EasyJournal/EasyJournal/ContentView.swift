import SwiftUI

struct ContentView: View {
    @State private var isRecording = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Journal Agent")
                .font(.largeTitle)
                .bold()

            Text(isRecording ? "Recording..." : "Tap to start")

            Button {
                isRecording.toggle()
            } label: {
                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
                    .frame(width: 90, height: 90)
                    .background(isRecording ? Color.red : Color.blue)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                isRecording ? "Stop recording" : "Start recording"
            )
        }
        .padding(40)
        .frame(minWidth: 400, minHeight: 300)
    }
}

#Preview {
    ContentView()
}
