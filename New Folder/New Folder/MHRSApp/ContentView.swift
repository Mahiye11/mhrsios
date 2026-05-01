import SwiftUI
enum AppLang: String, CaseIterable, Identifiable {
    case tr = "Türkçe"
    case en = "English"
    var id: String { rawValue }
}

// MARK: - View
struct ContentView: View {
    @State private var lang: AppLang = .tr
    @State private var tc = ""
    @State private var password = ""
    @State private var pushHome = false
    @State private var pushSignup = false
    @StateObject private var vm = LoginViewModel()
    @FocusState private var focusedField: Field?
    @State private var isPasswordVisible = false
    
    // SES YÖNETİCİSİ
    @StateObject private var voiceManager = VoiceManager()

    enum Field { case tc, password }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    
                    VStack(spacing: 8) {
                        Image("IMG_8420") // Assets'e koyduğun resmin adı
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
                    // TC
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
                    .focused($focusedField, equals: .tc)
                    .onSubmit { focusedField = .password }

                    // Şifre
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
                    //Giriş
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

                    // Sesli komut alanı
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
                                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: voiceManager.isListening)
                        

                        
                    }
                    .padding(.top, 12)
                }
                .padding(20)
            }
            .navigationDestination(isPresented: $pushHome) {  AnaSayfa()  }
            .navigationDestination(isPresented: $pushSignup) { UyeOlView()  }
            .alert("Hata", isPresented: .constant(vm.error != nil), actions: {
                Button("Tamam") { vm.error = nil }
            }, message: {
                Text(vm.error ?? "")
            })
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Button("Kapat") {
                        focusedField = nil
                    }
                }
            }
            // MARK: - Sesli Asistan Entegrasyonu
            .onAppear {
                // View açıldığında callbackleri tanımla ve asistanı başlat
                voiceManager.onTCDidChange = { spokenTC in
                    self.tc = spokenTC
                }
                voiceManager.onPasswordDidChange = { spokenPassword in
                    self.password = spokenPassword
                }
                voiceManager.onLoginTrigger = {
                    Task { await doLogin() }
                }
                
                // Biraz gecikmeli başlatmak UX açısından daha iyidir
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    voiceManager.startInitialFlow()
                }
            }
            .onDisappear {
                // Ekrandan çıkarken mikrofonu kapat
                voiceManager.stopListening()
            }
        }
    }

   
    private func doLogin() async {
        voiceManager.stopListening() // Manuel girişe basılırsa mikrofonu kapat
        focusedField = nil
        if await vm.login(tc: tc, password: password) {
            withAnimation { pushHome = true }
        }
    }
}
#Preview {
    ContentView()
}
