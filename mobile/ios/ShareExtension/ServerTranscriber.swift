import Foundation

/// Minimal multipart uploader for the Share Extension's server fallback.
/// Posts the shared file to `/transcribe` with the user's bearer token (read
/// from the App Group) and parses the JSON the backend returns. Mirrors the
/// fields the Flutter `Transcription.fromApiResponse` reads.
/// User-facing failure carried by this file's `Result`s.
///
/// `Result`'s failure type must conform to `Error`, and `String` does not — the
/// original code used `Result<_, String>`, which is why this whole target never
/// compiled (and therefore never shipped: the built app had no PlugIns folder).
/// Conforming to `ExpressibleByStringInterpolation` keeps every existing
/// `completion(.failure("رسالة"))` call site working verbatim.
struct TranscribeError: Error, ExpressibleByStringInterpolation, CustomStringConvertible {
  let message: String

  init(_ message: String) { self.message = message }
  init(stringLiteral value: String) { self.message = value }
  init(stringInterpolation: DefaultStringInterpolation) {
    self.message = String(stringInterpolation: stringInterpolation)
  }

  var description: String { message }
}

enum ServerTranscriber {

  struct Response {
    let text: String
    let lang: String?
    let langName: String?
    let wordCount: Int?
    let duration: Double?
    let requestId: Int?
  }

  static func transcribe(
    fileURL: URL,
    baseUrl: String,
    token: String,
    highQuality: Bool = false,
    completion: @escaping (Result<Response, TranscribeError>) -> Void
  ) {
    guard let url = URL(string: "\(baseUrl)/transcribe") else {
      completion(.failure("عنوان الخادم غير صالح.")); return
    }
    guard let fileData = try? Data(contentsOf: fileURL) else {
      completion(.failure("تعذّر قراءة الملف الصوتي.")); return
    }

    let boundary = "Boundary-\(UUID().uuidString)"
    var req = URLRequest(url: url, timeoutInterval: 120)
    req.httpMethod = "POST"
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

    let filename = fileURL.lastPathComponent
    let mime = mimeType(for: fileURL.pathExtension.lowercased())

    var body = Data()
    func appendField(_ name: String, _ value: String) {
      body.append("--\(boundary)\r\n".data(using: .utf8)!)
      body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
      body.append("\(value)\r\n".data(using: .utf8)!)
    }
    // File part.
    body.append("--\(boundary)\r\n".data(using: .utf8)!)
    body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
    body.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
    body.append(fileData)
    body.append("\r\n".data(using: .utf8)!)
    // Backend Literal: upload | recording | share | api.
    appendField("source", "share")
    appendField("is_live_recording", "false")
    // Premium re-do: ask the backend for its higher-quality pass (billed 2×).
    if highQuality {
      appendField("high_quality", "true")
    }
    body.append("--\(boundary)--\r\n".data(using: .utf8)!)
    req.httpBody = body

    URLSession.shared.dataTask(with: req) { data, resp, error in
      if let error = error {
        completion(.failure("تعذّر الاتصال بالخادم: \(error.localizedDescription)"))
        return
      }
      let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
      guard let data = data else {
        completion(.failure("لم يرد الخادم بأي بيانات.")); return
      }
      if status == 401 {
        completion(.failure("انتهت صلاحية جلستك. افتح التطبيق وسجّل الدخول.")); return
      }
      if status == 429 {
        completion(.failure("لقد بلغت الحد اليومي للتحويلات. حاول لاحقاً أو افتح التطبيق."))
        return
      }
      guard (200...299).contains(status) else {
        completion(.failure("فشل التحويل عبر الخادم (رمز \(status))."))
        return
      }
      guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        completion(.failure("رد غير متوقع من الخادم.")); return
      }
      let text = (json["text"] as? String) ?? ""
      let response = Response(
        text: text,
        lang: json["lang"] as? String,
        langName: json["lang_name"] as? String,
        wordCount: json["word_count"] as? Int,
        duration: (json["duration"] as? NSNumber)?.doubleValue,
        requestId: json["request_id"] as? Int
      )
      completion(.success(response))
    }.resume()
  }

  /// Translates a transcript to Arabic via `/transcriptions/translate` (costs
  /// the user 1 daily credit, charged server-side only on success). Returns the
  /// Arabic text. Mirrors the Flutter `transcription_repository.translate`.
  static func translate(
    text: String,
    sourceLang: String?,
    baseUrl: String,
    token: String,
    completion: @escaping (Result<String, TranscribeError>) -> Void
  ) {
    guard let url = URL(string: "\(baseUrl)/transcriptions/translate") else {
      completion(.failure("عنوان الخادم غير صالح.")); return
    }
    var req = URLRequest(url: url, timeoutInterval: 120)
    req.httpMethod = "POST"
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    // Backend caps text at 50k chars (422 otherwise); clamp to match.
    var payload: [String: Any] = ["text": String(text.prefix(50_000))]
    if let sl = sourceLang, !sl.isEmpty { payload["source_lang"] = sl }
    req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

    URLSession.shared.dataTask(with: req) { data, resp, error in
      if let error = error {
        completion(.failure("تعذّر الاتصال بالخادم: \(error.localizedDescription)"))
        return
      }
      let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
      guard let data = data else {
        completion(.failure("لم يرد الخادم بأي بيانات.")); return
      }
      if status == 401 {
        completion(.failure("انتهت صلاحية جلستك. افتح التطبيق وسجّل الدخول.")); return
      }
      if status == 429 {
        completion(.failure("لقد بلغت الحد اليومي. حاول لاحقاً أو افتح التطبيق.")); return
      }
      guard (200...299).contains(status) else {
        completion(.failure("فشلت الترجمة (رمز \(status))."))
        return
      }
      guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let translated = (json["translated_text"] as? String)?
              .trimmingCharacters(in: .whitespacesAndNewlines),
            !translated.isEmpty else {
        completion(.failure("تعذّرت الترجمة. حاول مرة أخرى.")); return
      }
      completion(.success(translated))
    }.resume()
  }

  private static func mimeType(for ext: String) -> String {
    switch ext {
    case "mp3": return "audio/mpeg"
    case "m4a", "mp4": return "audio/mp4"
    case "wav": return "audio/wav"
    case "ogg", "opus": return "audio/ogg"
    case "flac": return "audio/flac"
    case "aac": return "audio/aac"
    case "amr": return "audio/amr"
    case "caf": return "audio/x-caf"
    case "aiff": return "audio/aiff"
    default: return "application/octet-stream"
    }
  }
}
