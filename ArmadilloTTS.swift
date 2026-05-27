//
//  ArmadilloTTS.swift — Text-to-speech opzionale via ElevenLabs.
//  © 2026 Andrea Ricciotti / PunxCode — MIT (vedi LICENSE).
//
//  ──────────────────────────────────────────────────────────────────────
//  FEATURE OPT-IN. Disattivata di default: l'app resta offline e usa i clip
//  audio statici. Se l'utente fornisce una propria API key ElevenLabs e un
//  voice_id (vedi scripts/clone-voice.sh), le frasi dell'Armadillo Clippy
//  vengono sintetizzate dinamicamente e messe in cache su disco.
//
//  Nessuna voce, chiave o voice_id è inclusa nel sorgente. La voce vive
//  esclusivamente sull'account ElevenLabs dell'utente. Vedi l'avviso ToS in
//  scripts/clone-voice.sh.
//  ──────────────────────────────────────────────────────────────────────
//
import Foundation
import CryptoKit

/// Configurazione TTS, persistita in
/// ~/Library/Application Support/ArmadilloBar/tts.json
struct TTSConfig: Codable {
    var enabled: Bool
    var apiKey: String
    var voiceId: String
    var modelId: String
    // Voice settings (default tarati sul clone "Armadillo" — vedi README).
    var stability: Double
    var similarityBoost: Double
    var style: Double

    enum CodingKeys: String, CodingKey {
        case enabled
        case apiKey = "api_key"
        case voiceId = "voice_id"
        case modelId = "model_id"
        case stability
        case similarityBoost = "similarity_boost"
        case style
    }

    // I voice_settings sono opzionali nel file: se assenti usa i default.
    init(enabled: Bool, apiKey: String, voiceId: String, modelId: String,
         stability: Double = 0.3, similarityBoost: Double = 0.9, style: Double = 0.3) {
        self.enabled = enabled
        self.apiKey = apiKey
        self.voiceId = voiceId
        self.modelId = modelId
        self.stability = stability
        self.similarityBoost = similarityBoost
        self.style = style
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        voiceId = try c.decodeIfPresent(String.self, forKey: .voiceId) ?? ""
        modelId = try c.decodeIfPresent(String.self, forKey: .modelId) ?? "eleven_multilingual_v2"
        stability = try c.decodeIfPresent(Double.self, forKey: .stability) ?? 0.3
        similarityBoost = try c.decodeIfPresent(Double.self, forKey: .similarityBoost) ?? 0.9
        style = try c.decodeIfPresent(Double.self, forKey: .style) ?? 0.3
    }

    static let empty = TTSConfig(enabled: false, apiKey: "", voiceId: "",
                                 modelId: "eleven_multilingual_v2")

    /// Pronta all'uso solo se attiva e con chiave + voce valorizzate.
    var isUsable: Bool {
        enabled && !apiKey.isEmpty && !voiceId.isEmpty
    }
}

/// Genera (o recupera da cache) clip audio per una frase, usando la voce
/// clonata dell'utente su ElevenLabs. Tutte le callback tornano sulla main queue.
final class ArmadilloTTS {

    static let shared = ArmadilloTTS()

    private let fm = FileManager.default
    private let session: URLSession

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        cfg.waitsForConnectivity = false
        session = URLSession(configuration: cfg)
    }

    // MARK: - Paths

    private var supportDir: URL {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ArmadilloBar", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var configURL: URL { supportDir.appendingPathComponent("tts.json") }

    private var cacheDir: URL {
        let dir = supportDir.appendingPathComponent("tts-cache", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Config persistence

    func loadConfig() -> TTSConfig {
        guard let data = try? Data(contentsOf: configURL),
              let cfg = try? JSONDecoder().decode(TTSConfig.self, from: data)
        else { return .empty }
        return cfg
    }

    func saveConfig(_ cfg: TTSConfig) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(cfg) {
            try? data.write(to: configURL, options: .atomic)
        }
    }

    var isEnabled: Bool { loadConfig().isUsable }

    // MARK: - Cache

    /// Chiave di cache stabile: hash di (voice_id + model_id + testo). Cambiando
    /// voce o modello si rigenera, stesso testo+voce riusa il file esistente.
    private func cacheURL(for text: String, cfg: TTSConfig) -> URL {
        let seed = "\(cfg.voiceId)|\(cfg.modelId)|\(cfg.stability)|\(cfg.similarityBoost)|\(cfg.style)|\(text)"
        let digest = SHA256.hash(data: Data(seed.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return cacheDir.appendingPathComponent("\(hex).mp3")
    }

    // MARK: - Synthesis

    /// Recupera l'audio per `text`: da cache se presente, altrimenti lo genera
    /// via ElevenLabs e lo mette in cache. `completion(nil)` se TTS è disattivo
    /// o la richiesta fallisce (il chiamante fa fallback al solo balloon).
    func audioURL(for text: String, completion: @escaping (URL?) -> Void) {
        let cfg = loadConfig()
        guard cfg.isUsable else { complete(completion, nil); return }

        let cached = cacheURL(for: text, cfg: cfg)
        if fm.fileExists(atPath: cached.path) {
            complete(completion, cached)
            return
        }

        guard let voiceEscaped = cfg.voiceId.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed),
              let url = URL(string:
                "https://api.elevenlabs.io/v1/text-to-speech/\(voiceEscaped)?output_format=mp3_44100_128")
        else { complete(completion, nil); return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(cfg.apiKey, forHTTPHeaderField: "xi-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        let body: [String: Any] = [
            "text": text,
            "model_id": cfg.modelId,
            "voice_settings": [
                "stability": cfg.stability,
                "similarity_boost": cfg.similarityBoost,
                "style": cfg.style,
                "use_speaker_boost": true,
            ],
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        session.dataTask(with: req) { [weak self] data, resp, _ in
            guard let self else { return }
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let data, !data.isEmpty,
                  // Sanity: 200 con corpo JSON = errore mascherato, non audio.
                  data.first != UInt8(ascii: "{")
            else { self.complete(completion, nil); return }

            do {
                try data.write(to: cached, options: .atomic)
                self.complete(completion, cached)
            } catch {
                self.complete(completion, nil)
            }
        }.resume()
    }

    private func complete(_ cb: @escaping (URL?) -> Void, _ url: URL?) {
        DispatchQueue.main.async { cb(url) }
    }
}
