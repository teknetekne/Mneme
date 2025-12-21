import SwiftUI

struct TutorialView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentPage = 0
    let onComplete: () -> Void
    
    private let pages = [
        TutorialPage(
            image: "sparkles",
            title: "Welcome to Mneme",
            description: "Your intelligent daily companion. Mneme turns your thoughts into organized data using advanced on-device AI.",
            color: .blue
        ),
        TutorialPage(
            image: "mic.fill",
            title: "Just Say It",
            description: "Type or speak naturally. Mneme understands:\n\n• \"Meeting with team tomorrow at 10am @Apple Park\"\n• \"Read https://apple.com\"\n• \"Spent $50 on groceries\"\n• \"Ran 5km in 30 mins\"",
            color: .purple
        ),
        TutorialPage(
            image: "face.smiling.inverse",
            title: "Track Your Mood",
            description: "Type ':' to open the symbol picker. Select a mood emoji to start your journal entry.\n\nExample:\nType ':' → Select 😊 → \"Had a productive day!\"",
            color: .orange
        ),
        TutorialPage(
            image: "chart.bar.fill",
            title: "Gain Insights",
            description: "See your daily habits, spending, and health trends visualize automatically in the Summary tab.",
            color: .green
        )
    ]
    
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        TutorialPageView(page: pages[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                .animation(.easeInOut(duration: 0.5), value: currentPage)
                
                VStack(spacing: 20) {
                    if currentPage == pages.count - 1 {
                        Button {
                            onComplete()
                            dismiss()
                        } label: {
                            Text("Get Started")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Color.accentColor)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .padding(.horizontal, 40)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    } else {
                        Button {
                            withAnimation(.easeInOut(duration: 0.6)) {
                                currentPage += 1
                            }
                        } label: {
                            Text("Next")
                                .font(.headline)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .padding(.bottom, 50)
            }
        }
    }
}

struct TutorialPage {
    let image: String
    let title: String
    let description: String
    let color: Color
}

struct TutorialPageView: View {
    let page: TutorialPage
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            Circle()
                .fill(page.color.opacity(0.1))
                .frame(width: 200, height: 200)
                .overlay {
                    Image(systemName: page.image)
                        .font(.system(size: 80))
                        .foregroundStyle(page.color)
                }
            
            VStack(spacing: 16) {
                Text(page.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                
                Text(page.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .lineSpacing(4)
            }
            
            Spacer()
        }
        .padding(.top, 40)
    }
}

#Preview {
    TutorialView(onComplete: {})
}
