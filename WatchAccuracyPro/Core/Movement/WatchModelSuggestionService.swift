import Foundation

/// Sprint 5 (P2-2): 시계 모델명 자동완성 서비스.
/// 앱 번들 내 popularBrands 리스트 + 유명 모델 내장 DB로 자동완성 제공.
/// 네트워크 없이 완전 온디바이스 동작.
enum WatchModelSuggestionService {

    // MARK: - 브랜드별 대표 모델 DB (상위 20개 브랜드 × 5~10개 모델)
    private static let modelDB: [String: [String]] = [
        "Rolex": ["Submariner", "Submariner Date", "Datejust", "GMT-Master II",
                  "Day-Date", "Daytona", "Explorer", "Explorer II", "Sea-Dweller", "Sky-Dweller"],
        "Omega": ["Speedmaster Moonwatch", "Speedmaster Professional", "Seamaster 300M",
                  "Seamaster Aqua Terra", "Constellation", "De Ville Tresor", "Planet Ocean"],
        "IWC": ["Portugieser", "Pilot's Watch", "Portofino", "Ingenieur",
                "Aquatimer", "Da Vinci", "Big Pilot"],
        "Patek Philippe": ["Nautilus", "Aquanaut", "Calatrava", "Complications",
                           "Grand Complications", "Gondolo", "Twenty-4"],
        "Audemars Piguet": ["Royal Oak", "Royal Oak Offshore", "Royal Oak Concept",
                             "Code 11.59", "Millenary", "Jules Audemars"],
        "Seiko": ["SKX007", "SARB065", "Presage", "Prospex", "Astron",
                  "5 Sports", "King Seiko", "Grand Seiko"],
        "Grand Seiko": ["SBGA211", "SBGW231", "SBGH267", "SBGA413", "SLGH005"],
        "Tudor": ["Black Bay", "Black Bay Pro", "Pelagos", "Glamour Date",
                  "Royal", "Ranger", "Heritage Chrono"],
        "Cartier": ["Tank", "Santos", "Ballon Bleu", "Panthère", "Clé de Cartier",
                    "Ronde", "Drive de Cartier", "Pasha"],
        "Jaeger-LeCoultre": ["Reverso", "Master Control", "Polaris", "Atmos",
                              "Duomètre", "Geophysic"],
        "Breitling": ["Navitimer", "Superocean", "Avenger", "Premier",
                      "Chronomat", "Professional"],
        "TAG Heuer": ["Carrera", "Monaco", "Aquaracer", "Formula 1",
                      "Link", "Connected"],
        "Longines": ["HydroConquest", "Spirit", "Conquest", "Master Collection",
                     "Elegant", "Record"],
        "Tissot": ["PRX", "T-Classic", "Everytime", "Seastar",
                   "T-Race", "Le Locle"],
        "Hamilton": ["Khaki Field", "Khaki Navy", "Jazzmaster", "Ventura",
                     "American Classic", "Timeless Classic"],
        "Citizen": ["Promaster", "Eco-Drive", "Chandler", "Paradex"],
        "Casio": ["G-Shock", "Edifice", "Pro Trek", "Lineage",
                  "Databank", "F-91W"],
        "Nomos": ["Tangente", "Club", "Orion", "Metro", "Lambda", "Ahoi"],
        "Zenith": ["El Primero", "Chronomaster", "Defy", "Pilot"],
        "Panerai": ["Luminor", "Radiomir", "Submersible", "Luminor Due"],
    ]

    /// 브랜드 선택 시 해당 모델 후보 반환.
    static func models(for brand: String) -> [String] {
        modelDB[brand] ?? []
    }

    /// 브랜드 + 부분 입력 → 매칭 모델 목록.
    static func suggestions(brand: String, partialModel: String) -> [String] {
        let models = modelDB[brand] ?? []
        guard !partialModel.isEmpty else { return models }
        let q = partialModel.lowercased()
        return models.filter { $0.lowercased().contains(q) }
    }

    /// 전체 브랜드에서 자연어 검색 ("Rolex Sub" → [Submariner, ...]).
    static func globalSearch(_ query: String) -> [(brand: String, model: String)] {
        let q = query.lowercased()
        guard !q.isEmpty else { return [] }
        var results: [(brand: String, model: String)] = []
        for (brand, models) in modelDB {
            if brand.lowercased().contains(q) {
                for model in models.prefix(3) {
                    results.append((brand: brand, model: model))
                }
            } else {
                for model in models {
                    if model.lowercased().contains(q) {
                        results.append((brand: brand, model: model))
                    }
                }
            }
        }
        return Array(results.prefix(10))
    }
}
