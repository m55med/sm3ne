import Foundation

/// Minimal multipart uploader for the Share Extension's server fallback.
/// Posts the shared file to `/transcribe` with the user's bearer token (read
/// from the App Group) and parses the JSON the backend returns. Mirrors the
/// fields the Flutter `Transcription.fromApiResponse` reads.
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
    completion: @escaping (Result<Response, String>) -> Void
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
