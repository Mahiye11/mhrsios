import SwiftUI

// MARK: - Dil
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

    enum Field { case tc, password }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Başlık
                    VStack(spacing: 8) {
                        Text("MHRS Giriş")
                            .font(.system(size: 34, weight: .bold))
                            .padding(.top, 16)

                        Text("Merkezi Hekim Randevu Sistemi")
                            .font(.system(size: 17))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)

                    // Dil seçimi
                    languageSwitcher

                    // TC
                    TextField("TC Kimlik Numarası", text: $tc)
                        .keyboardType(.numberPad)
                        .textContentType(.username)
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12).strokeBorder(Color.gray.opacity(0.15))
                        )
                        .focused($focusedField, equals: .tc)
                        .onSubmit { focusedField = .password } // Yeni eklenen satır

                    // Şifre
                    SecureField("Şifre", text: $password)
                        .textContentType(.password)
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12).strokeBorder(Color.gray.opacity(0.15))
                        )
                        .focused($focusedField, equals: .password)
                        .onSubmit { Task { await doLogin() } } // Yeni eklenen satır

                    // Giriş
                    Button {
                        Task { await doLogin() }
                    } label: {
                        HStack {
                            if vm.isLoading { ProgressView().tint(.white) }
                            Text("Giriş").fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .background(Color.green, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(.white)
                    .disabled(vm.isLoading)

                    // Üye Ol
                    NavigationLink {
                        UyeOlView()
                    } label: {
                        Text("Üye Ol")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(.white)

                    // Sesli komut alanı
                    VStack(spacing: 12) {
                        Text("Sesli komutla devam etmek ister misiniz?")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        // Ses dalgası resminin assets içinde doğru adla ve uzantıyla yer aldığından emin olun.
                        NavigationLink(destination: MedAsistanView()) {
                            Image("sesdalgası")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 90, height: 90)
                                .padding(.top, 4)
                        }

                        Text("Soru ve sorunlarınız için")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                    .padding(.top, 12)
                }
                .padding(20)
            }
            .navigationDestination(isPresented: $pushHome) { AnaSayfa() }
            .navigationDestination(isPresented: $pushSignup) { UyeOlView() }
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
        }
    }

    // Dil switcher
    private var languageSwitcher: some View {
        HStack(spacing: 0) {
            langButton(.tr, isFirst: true)
            langButton(.en, isFirst: false)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.gray.opacity(0.12))
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.top, 6)
    }

    private func langButton(_ l: AppLang, isFirst: Bool) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { lang = l }
        } label: {
            Text(l.rawValue)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    Group {
                        if lang == l {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.white)
                                .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                        } else {
                            Color.clear
                        }
                    }
                )
        }
        .buttonStyle(.plain)
    }

    // Login tetikleyici
    private func doLogin() async {
        focusedField = nil // Klavyeyi kapatmak için focus'u sıfırlıyoruz.
        if await vm.login(tc: tc, password: password) {
            withAnimation { pushHome = true }
        }
    }
}

#Preview {
    ContentView()
}
