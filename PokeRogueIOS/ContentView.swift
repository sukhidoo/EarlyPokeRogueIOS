import SwiftUI

struct ContentView: View {
    @State private var isLoading = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background color to match game theme
                Color.black
                    .ignoresSafeArea(.all)
                
                // Web view with proper frame constraints
                WebView()
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height
                    )
                    .clipped()
                    .ignoresSafeArea(.all)
                
                // Loading overlay
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        
                        Text("Loading PokéRogue...")
                            .foregroundColor(.white)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        Color.black.opacity(0.8)
                            .ignoresSafeArea(.all)
                    )
                    .transition(.opacity)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // Show loading initially
            isLoading = true
            
            // Hide loading after game has time to load
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                withAnimation(.easeOut(duration: 0.5)) {
                    isLoading = false
                }
            }
        }
        .navigationBarHidden(true)
        .statusBarHidden(true)
    }
}

#Preview {
    ContentView()
}
