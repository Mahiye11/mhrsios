/*import SwiftUI

// MARK: - DTO'lar (DB şemanla birebir aynı isimler)
struct IlDTO: Identifiable, Decodable, Hashable {
    let id: Int
    let ad: String
}

struct IlceDTO: Identifiable, Decodable, Hashable {
    let id: Int
    let ad: String
    let il_id: Int
}

struct HastaneDTO: Identifiable, Decodable, Hashable {
    let id: Int
    let ad: String
    let ilce_id: Int?
}

struct DoctorDTO: Identifiable, Decodable, Hashable {
    let id: Int
    let doktor_ad: String
    let hastane_id: Int?
    let hastane_ad: String?
}

// MARK: - API
enum APIError: Error { case invalidResponse(Int), decoding(Error) }


// MARK: - View
struct HastaneRandevuView: View {
    @State private var iller: [IlDTO] = []
    @State private var ilceler: [IlceDTO] = []
    @State private var hastaneler: [HastaneDTO] = []
    @State private var doktorlar: [DoctorDTO] = []

    @State private var secilenIl: IlDTO?
    @State private var secilenIlce: IlceDTO?
    @State private var secilenHastane: HastaneDTO?
    @State private var secilenDoktor: DoctorDTO?

    @State private var secilenKlinik = ""
    @State private var secilenMuayeneYeri = ""
    @State private var baslangicTarihi = Date()
    @State private var bitisTarihi = Date()

    let klinikler = ["", "Aile Hekimliği", "Kardiyoloji", "Nöroloji", "FTR"]
    let muayeneYerleri = ["", "Poliklinik 1", "Poliklinik 2", "Acil"]

    var body: some View {
        NavigationView {
            Form {
                Section {
                    // İl
                    Picker("İl", selection: $secilenIl) {
                        Text("").tag(nil as IlDTO?)
                        ForEach(iller) { il in
                            Text(il.ad).tag(Optional(il))
                        }
                    }
                    .onChange(of: secilenIl, initial: false) { _, yeniIl in
                        Task {
                            await MainActor.run {
                                secilenIlce = nil; ilceler = []
                                secilenHastane = nil; hastaneler = []
                                secilenDoktor = nil; doktorlar = []
                            }
                            guard let yeniIl else { return }
                            do {
                                let data = try await API.districts(il: yeniIl)
                                await MainActor.run { ilceler = data }
                            } catch { print("districts error:", error) }
                        }
                    }

                    // İlçe
                    Picker("İlçe", selection: $secilenIlce) {
                        Text("").tag(Optional<IlceDTO>.none)
                        ForEach(ilceler) { i in
                            Text(i.ad).tag(Optional(i))
                        }
                    }
                    .onChange(of: secilenIlce, initial: false) { _, yeniIlce in
                        Task {
                            await MainActor.run {
                                secilenHastane = nil; hastaneler = []
                                secilenDoktor = nil; doktorlar = []
                            }
                            guard let yeniIlce else { return }
                            do {
                                let data = try await API.hospitals(ilce: yeniIlce)
                                await MainActor.run { hastaneler = data }
                            } catch { print("hospitals error:", error) }
                        }
                    }

                    // Hastane
                    Picker("Hastane", selection: $secilenHastane) {
                        Text("").tag(Optional<HastaneDTO>.none)
                        ForEach(hastaneler) { h in
                            Text(h.ad).tag(Optional(h))
                        }
                    }
                    .onChange(of: secilenHastane, initial: false) { _, yeniHastane in
                        Task {
                            await MainActor.run { secilenDoktor = nil; doktorlar = [] }
                            guard let h = yeniHastane else { return }
                            do {
                                let docs = try await API.doctors(hastane: h)
                                await MainActor.run { doktorlar = docs }
                            } catch { print("doctors error:", error) }
                        }
                    }

                    // Doktor
                    Picker("Doktor", selection: $secilenDoktor) {
                        Text("").tag(Optional<DoctorDTO>.none)
                        ForEach(doktorlar) { d in
                            Text(d.doktor_ad).tag(Optional(d))
                        }
                    }
                    .onChange(of: secilenDoktor, initial: false) { _, yeniDoktor in
                        guard let d = yeniDoktor else { return }
                        print("Seçilen doktor ID:", d.id)
                        print("Seçilen doktor Adı:", d.doktor_ad)
                    }

                    // Klinik
                    Picker("Klinik", selection: $secilenKlinik) {
                        ForEach(klinikler, id: \.self) { Text($0).tag($0) }
                    }

                    // Muayene Yeri
                    Picker("Muayene Yeri", selection: $secilenMuayeneYeri) {
                        ForEach(muayeneYerleri, id: \.self) { Text($0).tag($0) }
                    }
                }

                Section {
                    DatePicker("Başlangıç", selection: $baslangicTarihi, displayedComponents: .date)
                    DatePicker("Bitiş", selection: $bitisTarihi, displayedComponents: .date)

                    Button("🔍 Randevu Ara") {
                        print("İl:", secilenIl?.ad ?? "-")
                        print("İlçe:", secilenIlce?.ad ?? "-")
                        print("Hastane:", secilenHastane?.ad ?? "-")
                        print("Doktor:", secilenDoktor?.doktor_ad ?? "-")
                        print("Klinik:", secilenKlinik)
                        print("Muayene Yeri:", secilenMuayeneYeri)
                    }
                    .frame(maxWidth: .infinity).padding()
                    .background(Color.blue).foregroundColor(.white).cornerRadius(10)

                    Button("🗑️ Temizle") { temizle() }
                        .frame(maxWidth: .infinity).padding()
                        .background(Color.red).foregroundColor(.white).cornerRadius(10)
                }
            }
            .navigationTitle("Randevu Ara")
            .task { await illeriYukle() }
        }
    }

    private func temizle() {
        secilenIl = nil
        secilenIlce = nil; ilceler = []
        secilenHastane = nil; hastaneler = []
        secilenDoktor = nil; doktorlar = []
        secilenKlinik = ""
        secilenMuayeneYeri = ""
        baslangicTarihi = Date()
        bitisTarihi = Date()
    }

    private func illeriYukle() async {
        do {
            iller = try await API.cities()
        } catch {
            print("cities error:", error)
        }
    }
}

#Preview { HastaneRandevuView() }
*/
