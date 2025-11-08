//
//  TimelineFeedbackModal.swift
//  Dayflow
//
//  Feedback card shown after rating a timeline summary.
//

import SwiftUI

enum TimelineFeedbackMode {
    case form
    case thanks
}

struct TimelineFeedbackModal: View {
    @Binding var message: String
    @Binding var shareLogs: Bool
    let direction: TimelineRatingDirection
    let mode: TimelineFeedbackMode
    let onSubmit: () -> Void
    let onClose: () -> Void
    let onConfigureCategories: (() -> Void)?

    @FocusState private var isEditorFocused: Bool

    private let placeholder = "I don’t have access to your timeline (privacy first!), so your feedback is the only window into how well the timeline is working. If you’re up for elaborating, it really helps improve the product for everyone."

    var body: some View {
        ZStack(alignment: .topTrailing) {
            modalCard

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(Color(hex: "FF8046").opacity(0.7))
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(0.9))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .offset(x: -8, y: 6)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Timeline feedback form")
        .accessibilityHint("Share more context after rating this summary.")
    }

    @ViewBuilder
    private var modalCard: some View {
        VStack(spacing: mode == .form ? 20 : 24) {
            switch mode {
            case .form:
                formContent
            case .thanks:
                thanksContent
            }
        }
        .padding(24)
        .frame(width: 286)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color(hex: "FFF4E9"), location: 0),
                            .init(color: Color.white, location: 0.85)
                        ]),
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(hex: "ECECEC"), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.07), radius: 12, x: 0, y: 6)
    }

    private var formContent: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                Text("Thank you!")
                    .font(Font.custom("InstrumentSerif-Regular", size: 18))
                    .foregroundColor(Color(hex: "333333"))
                    .multilineTextAlignment(.center)

                Text("Tell us more about your feedback")
                    .font(Font.custom("Nunito", size: 13).weight(.medium))
                    .foregroundColor(Color(hex: "333333"))
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 8) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $message)
                        .font(Font.custom("Nunito", size: 12).weight(.medium))
                        .foregroundColor(Color(hex: "333333"))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 8)
                        .background(Color.white)
                        .frame(height: 90)
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color(hex: "D9D9D9"), lineWidth: 1)
                        )
                        .focused($isEditorFocused)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                isEditorFocused = true
                            }
                        }
                        .scrollContentBackground(.hidden)

                    if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(placeholder)
                            .font(Font.custom("Nunito", size: 12).weight(.medium))
                            .foregroundColor(Color(hex: "AAAAAA"))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                    }
                }

                HStack(alignment: .top, spacing: 8) {
                    Button {
                        shareLogs.toggle()
                    } label: {
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Color(hex: "FF8046"), lineWidth: shareLogs ? 0 : 1)
                            .frame(width: 14, height: 14)
                            .overlay(
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.white)
                                    .opacity(shareLogs ? 1 : 0)
                            )
                            .background(
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(shareLogs ? Color(hex: "FF8046") : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)

                    Text("I’d like to share this log to the developer to help improve the product.")
                        .font(Font.custom("Nunito", size: 10).weight(.medium))
                        .foregroundColor(Color.black)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button(action: onSubmit) {
                Text("Submit")
                    .font(Font.custom("Nunito", size: 12).weight(.medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .background(Color(hex: "FF8046"))
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
        }
    }

    private var thanksContent: some View {
        VStack(spacing: 20) {
            Text("Thank you for your feedback!")
                .font(Font.custom("InstrumentSerif-Regular", size: 18))
                .foregroundColor(Color(hex: "333333"))
                .multilineTextAlignment(.center)
                .padding(.bottom, 4)

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("If you find that your activities are summarized inaccurately, try editing the descriptions of your categories to improve Dayflow’s accuracy.")
                        .font(Font.custom("Nunito", size: 12).weight(.medium))
                        .foregroundColor(Color(hex: "333333"))
                        .multilineTextAlignment(.leading)

                    categoryTipsIllustration
                }

                Button {
                    onConfigureCategories?()
                } label: {
                    Text("Configure categories")
                        .font(Font.custom("Nunito", size: 12).weight(.medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(Color(hex: "402B00"))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

extension TimelineFeedbackModal {
    private var categoryTipsIllustration: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.92, blue: 0.84),
                                Color(red: 1.0, green: 0.82, blue: 0.63)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.7), lineWidth: 0.5)
                    )

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(red: 0.45, green: 0.22, blue: 0.02))
                            .padding(6)
                            .background(Color.white.opacity(0.8))
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Category tips")
                                .font(Font.custom("Nunito", size: 11).weight(.semibold))
                                .foregroundColor(Color(red: 0.35, green: 0.16, blue: 0))

                            Text("Tighten up your category descriptions to help Dayflow understand what you’re working on.")
                                .font(Font.custom("Nunito", size: 10))
                                .foregroundColor(Color(red: 0.35, green: 0.16, blue: 0).opacity(0.8))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Text("Tip: Mention tools, meeting names, or the outcomes you expect (e.g. ‘Summaries ▸ Weekly project update with task outcomes’).")
                        .font(Font.custom("Nunito", size: 10))
                        .foregroundColor(Color(red: 0.35, green: 0.16, blue: 0).opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(width: geometry.size.width, alignment: .leading)
            }
        }
        .frame(height: 120)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    TimelineFeedbackModal(
        message: .constant(""),
        shareLogs: .constant(true),
        direction: .up,
        mode: .form,
        onSubmit: {},
        onClose: {},
        onConfigureCategories: nil
    )
    .padding()
    .background(Color.gray.opacity(0.1))

    TimelineFeedbackModal(
        message: .constant(""),
        shareLogs: .constant(true),
        direction: .up,
        mode: .thanks,
        onSubmit: {},
        onClose: {},
        onConfigureCategories: {}
    )
    .padding()
    .background(Color.gray.opacity(0.1))
}
