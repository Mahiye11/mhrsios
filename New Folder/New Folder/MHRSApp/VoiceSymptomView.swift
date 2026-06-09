import Foundation
import SwiftUI
import Speech
import AVFoundation

struct VoiceSymptomView: View {
    let userId: Int

    @StateObject private var vm = VoiceSymptomViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var inputText = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    vm.stopAll()
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Geri")
                    }
                    .font(.headline)
                    .foregroundColor(.blue)
                }

                Spacer()

                Text("Sağlık Asistanı")
                    .font(.title2.bold())

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Geri")
                }
                .font(.headline)
                .opacity(0)
            }
            .padding()
            .background(Color.white)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(vm.messages) { message in
                        ChatBubbleView(message: message)
                    }
                }
                .padding()
            }

            if !vm.clinicOptions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Klinik Seçenekleri")
                        .font(.headline)

                    ForEach(Array(vm.clinicOptions.enumerated()), id: \.offset) { index, clinic in
                        HStack {
                            Text("\(index + 1)")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(width: 30, height: 30)
                                .background(Color.orange)
                                .clipShape(Circle())

                            Text(clinic)
                                .font(.subheadline.bold())
                                .foregroundColor(.black)

                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }

                    Text("Sesli olarak birinci, ikinci, üçüncü diyebilir ya da bölüm adını söyleyebilirsiniz.")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.orange.opacity(0.12))
                .cornerRadius(16)
                .padding(.horizontal)
            }

            if !vm.recommendedClinic.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Seçilen Bölüm:")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))

                    Text(vm.recommendedClinic)
                        .font(.title3.bold())
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.blue)
                .cornerRadius(16)
                .padding(.horizontal)
            }

            if !vm.symptoms.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Toplanan Belirtiler")
                        .font(.headline)

                    ForEach(vm.symptoms, id: \.self) { symptom in
                        Text("• \(symptom)")
                            .font(.subheadline)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.blue.opacity(0.08))
            }

            HStack {
                TextField("Şikayetinizi yazın...", text: $inputText)
                    .padding()
                    .background(Color.gray.opacity(0.12))
                    .cornerRadius(22)

                Button {
                    let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)

                    if trimmed.isEmpty {
                        vm.toggleListening()
                    } else {
                        vm.handleUserText(trimmed)
                        inputText = ""
                    }
                } label: {
                    Image(systemName: inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "mic.fill" : "paperplane.fill")
                        .foregroundColor(.white)
                        .frame(width: 52, height: 52)
                        .background(
                            vm.isAssistantSpeaking ? Color.red :
                            vm.isListening ? Color.green :
                            Color.blue
                        )
                        .clipShape(Circle())
                }
            }
            .padding()
            .background(Color.white)
        }
        .navigationDestination(isPresented: $vm.shouldNavigateToAppointment) {
            HastaneRandevuView(
                userId: userId,
                initialClinic: vm.recommendedClinic
            )
        }
        .background(Color(.systemGray6))
        .onAppear {
            vm.start()
        }
        .onDisappear {
            vm.stopAll()
        }
    }
}

struct ChatBubbleView: View {
    let message: SymptomChatMessage

    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
            }

            Text(message.text)
                .padding()
                .background(message.isUser ? Color.blue : Color.white)
                .foregroundColor(message.isUser ? .white : .black)
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 2)
                .frame(maxWidth: 280, alignment: message.isUser ? .trailing : .leading)

            if !message.isUser {
                Spacer()
            }
        }
    }
}

struct SymptomChatMessage: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
}
