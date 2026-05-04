import SwiftUI

struct CardView: View {
    let prompt: String
    let answer: String
    let mnemonic: String?
    @Binding var isShowingAnswer: Bool

    private var cardTitle: String {
        isShowingAnswer ? "Question + Answer" : "Question"
    }

    private var footerText: String {
        isShowingAnswer ? "Tap to hide answer" : "Tap to reveal answer"
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: isShowingAnswer
                        ? [Color(red: 0.06, green: 0.44, blue: 0.37), Color(red: 0.10, green: 0.62, blue: 0.51)]
                        : [Color(red: 0.13, green: 0.22, blue: 0.43), Color(red: 0.28, green: 0.36, blue: 0.63)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(alignment: .leading, spacing: 18) {
                Text(cardTitle)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.18), in: Capsule())
                
                Spacer(minLength: 0)
                
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Question")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.75))
                        
                        Text(prompt)
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    if isShowingAnswer {
                        Divider()
                            .overlay(.white.opacity(0.25))
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Answer")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white.opacity(0.75))
                            
                            Text(answer)
                                .font(.system(size: 24, weight: .medium, design: .rounded))
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        
                        if let mnemonic, !mnemonic.isEmpty {
                            Divider()
                                .overlay(.white.opacity(0.25))
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Mnemonic")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white.opacity(0.75))
                                
                                Text(mnemonic)
                                    .font(.system(size: 18, weight: .medium, design: .rounded))
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Spacer(minLength: 0)
                
                Text(footerText)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .foregroundStyle(.white)
            .padding(24)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 360)
        .shadow(color: .black.opacity(0.12), radius: 18, y: 10)
        .onTapGesture {
            withAnimation(.spring(duration: 0.35)) {
                if !isShowingAnswer {
                    isShowingAnswer = true
                }
            }
        }
        .disabled(isShowingAnswer)
    }
}
