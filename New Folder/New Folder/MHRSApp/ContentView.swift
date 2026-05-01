import SwiftUI

enum AppLang: String, CaseIterable, Identifiable {
    case tr = "Türkçe"
    case en = "English"

    var id: String { rawValue }
}

struct ContentView: View {
    @State private var lang: AppLang = .tr
    @State private var tc = ""
    @State private var password = ""
    @State private var pushHome = false
    @State private var pushSignup = false

    @StateObject private var vm = LoginViewModel()
    @StateObject private var voiceManager = VoiceManager()
    
    @FocusState private var focusedField: Field?

    @State private var isPasswordVisible = false
    @State private var challengeCode = ""
    
    
    enum Field { case tc, password }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    VStack(spacing: 8) {
                        Image("IMG_8420")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 90, height: 90)
                            .clipShape(RoundedRectangle(cornerRadius: 20))

                        Text("MedSes Hoşgeldiniz!")
                            .font(.system(size: 34, weight: .bold))

                        Text("Sesli Randevu Sistemi")
                            .font(.system(size: 17))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)

                    HStack {
                        Image(systemName: "person.fill")
                            .foregroundStyle(.blue)

                        TextField("TC Kimlik Numarası", text: $tc)
                            .keyboardType(.numberPad)
                            .textContentType(.username)
                            .focused($focusedField, equals: .tc)
                    }
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12).strokeBorder(Color.blue.opacity(0.4))
                    )
                    .frame(width: 300)
                    .onSubmit { focusedField = .password }

                    HStack {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.blue)

                        if isPasswordVisible {
                            TextField("Şifre", text: $password)
                                .textContentType(.password)
                                .focused($focusedField, equals: .password)
                        } else {
                            SecureField("Şifre", text: $password)
                                .textContentType(.password)
                                .focused($focusedField, equals: .password)
                        }

                        Button {
                            isPasswordVisible.toggle()
                        } label: {
                            Image(systemName: isPasswordVisible ? "eye.fill" : "eye.slash.fill")
                                .foregroundStyle(.gray)
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12).strokeBorder(Color.blue.opacity(0.4))
                    )
                    .frame(width: 300)

                    HStack(spacing: 16) {
                        Button {
                            Task { await doLogin() }
                        } label: {
                            HStack {
                                if vm.isLoading { ProgressView().tint(.white) }
                                Text("Giriş").fontWeight(.semibold)
                            }
                            .frame(width: 110)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                        .disabled(vm.isLoading)

                        NavigationLink {
                             UyeOlView()
                        } label: {
                            Text("Üye Ol")
                                .fontWeight(.semibold)
                                .frame(width: 110)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)
                        .background(Color.red, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                    }

                    VStack(spacing: 12) {
                        Text("Sesli komutla devam etmek ister misiniz?")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        Image(systemName: "waveform")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 90, height: 90)
                            .padding(.top, 4)
                            .foregroundStyle(voiceManager.isListening ? Color.red : Color.blue)
                            .scaleEffect(voiceManager.isListening ? 1.1 : 1.0)
                            .animation(
                                .easeInOut(duration: 0.5).repeatForever(autoreverses: true),
                                value: voiceManager.isListening
                            )
                        if !challengeCode.isEmpty {
                            Text(challengeCode)
                                .font(.system(size: 40, weight: .bold))
                                .tracking(10) // aralıklı gösterir
                                .padding(.top, 10)
                        }
                            
                    }
                    .padding(.top, 12)
                }
                .padding(20)
            }
            .navigationDestination(isPresented: $pushHome) {
                AnaSayfa(
                    userId: vm.userId ?? 0,
                    userName: vm.userName ?? "Kullanıcı",
                    userTc: tc
                )
            }
            .navigationDestination(isPresented: $pushSignup) {
                UyeOlView()
            }
            .alert("Hata", isPresented: .constant(vm.error != nil)) {
                Button("Tamam") { vm.error = nil }
            } message: {
                Text(vm.error ?? "")
            }
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Button("Kapat") {
                        focusedField = nil
                    }
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    voiceManager.startInitialFlow()
                }

                voiceManager.onVoiceTCRecorded = { audioURL in
                    Task {
                        await sendVoiceTCToBackend(audioURL: audioURL)
                    }
                }
                voiceManager.onSignupSelected = {
                    pushSignup = true
                }
                voiceManager.onVoiceLoginRecorded = { audioURL in
                    Task {
                        await sendVoiceLoginToBackend(audioURL: audioURL)
                    }
                }

                
            }
        }
    }

    private func doLogin() async {
        voiceManager.stopListening()
        focusedField = nil

        if await vm.login(tc: tc, password: password) {
            withAnimation {
                pushHome = true
            }
        }
    }
    private func sendVoiceTCToBackend(audioURL: URL) async {
        do {
            var request = URLRequest(url: APIConfig.recognizeTcURL)
            request.httpMethod = "POST"

            let boundary = UUID().uuidString
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

            let audioData = try Data(contentsOf: audioURL)

            var body = Data()
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"file\"; filename=\"tc.wav\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
            body.append(audioData)
            body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

            request.httpBody = body

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                vm.error = "Sunucu cevabı alınamadı."
                return
            }

            guard 200..<300 ~= httpResponse.statusCode else {
                let message = String(data: data, encoding: .utf8) ?? "TC tanınamadı."
                vm.error = message
                return
            }
            let result = try JSONDecoder().decode(TCResponse.self, from: data)
            self.tc = result.tcKimlik

            self.challengeCode = String(Int.random(in: 1000...9999))

            let spaced = challengeCode.map { String($0) }.joined(separator: " ")
            voiceManager.speak("\(spaced) kodunu tek tek söyleyerek tekrar edin")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
                voiceManager.startRecordingVoiceForLogin()
            }

        } catch {
            vm.error = "Sesli TC hatası: \(error.localizedDescription)"
        }
    }
    private func sendVoiceLoginToBackend(audioURL: URL) async {
        do {
            var request = URLRequest(url: APIConfig.voiceLoginURL)
            request.httpMethod = "POST"

            let boundary = UUID().uuidString
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

            let audioData = try Data(contentsOf: audioURL)

            var body = Data()

            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"file\"; filename=\"voice_login.wav\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
            body.append(audioData)
            body.append("\r\n".data(using: .utf8)!)

            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"tcKimlik\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(tc)\r\n".data(using: .utf8)!)

            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"challengeCode\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(challengeCode)\r\n".data(using: .utf8)!)

            body.append("--\(boundary)--\r\n".data(using: .utf8)!)

            request.httpBody = body

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                vm.error = "Sunucu cevabı alınamadı."
                return
            }

            guard 200..<300 ~= httpResponse.statusCode else {
                let message = String(data: data, encoding: .utf8) ?? "Ses doğrulama başarısız."
                vm.error = message
                return
            }
            let result = try JSONDecoder().decode(LoginResponse.self, from: data)
            vm.userId = result.userId
            vm.userName = result.name
            
            withAnimation {
                pushHome = true
            }
            

        } catch {
            vm.error = "Sesli giriş hatası: \(error.localizedDescription)"
        }
    }
}

struct TCResponse: Codable {
    let tcKimlik: String
}

#Preview {
    ContentView()
}
