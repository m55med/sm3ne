import UIKit
import Social
import MobileCoreServices
import UniformTypeIdentifiers
import Speech
import AVFoundation

// Remote diag mirror so we can watch the extension flow from a device.
fileprivate func diag(_ tag: String, _ message: String) {
  NSLog("[DIAG \(tag)] \(message)")
  let base = AppGroup.apiBaseUrl()
  guard let url = URL(string: "\(base)/diag/log") else { return }
  var req = URLRequest(url: url, timeoutInterval: 4)
  req.httpMethod = "POST"
  req.setValue("application/json", forHTTPHeaderField: "Content-Type")
  let payload: [String: String] = [
    "tag": String(("ext-" + tag).prefix(40)),
    "msg": String(message.prefix(480)),
  ]
  if let body = try? JSONSerialization.data(withJSONObject: payload) {
    req.httpBody = body
    URLSession.shared.dataTask(with: req).resume()
  }
}

/// The Share Extension's main controller. Instead of bouncing the user into
/// the full app, it transcribes the shared voice note IN-PLACE and shows a
/// floating result sheet. Engine order: Apple Speech on-device first (free,
/// private, fast), then the server `/transcribe` fallback when on-device can't
/// handle the file. A "فتح في بصوتك" button hands off to the full app for the
/// rich result screen.
class ShareViewController: UIViewController {

  private var sheet: ResultSheetView!
  private var savedAudioPath: String?          // copy inside App Group container
  private var detectedExtension: String = "m4a"

  override func viewDidLoad() {
    super.viewDidLoad()
    diag("life", "viewDidLoad")
    // iOS presents a share extension via UISheetPresentationController — the
    // SYSTEM already supplies the dimmed host-app backdrop behind the sheet.
    // We must NOT cover it: keep the root view fully clear and make ONLY the
    // bottom card opaque, so the system dim + host snapshot shows through
    // everywhere above the card. (Adding our own fullscreen dim view is what
    // produced the solid-black background before.)
    view.backgroundColor = .clear
    view.isOpaque = false
    setupSheet()
    handleSharedAudio()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    clearBackgroundChain()
  }

  // viewIsAppearing fires after the view is in the window hierarchy — the
  // reliable place to clear the presentation container. On iOS 26 the sheet
  // container otherwise renders opaque (Liquid Glass, FB20934974); on 15–18
  // this is a harmless re-assert.
  @available(iOS 13.0, *)
  override func viewIsAppearing(_ animated: Bool) {
    super.viewIsAppearing(animated)
    clearBackgroundChain()
  }

  /// Clears the background of our view and every ancestor up to the window so
  /// nothing in OUR hierarchy hides the system's dim+host backdrop.
  private func clearBackgroundChain() {
    var v: UIView? = view
    while let cur = v {
      cur.backgroundColor = .clear
      cur.isOpaque = false
      v = cur.superview
    }
  }

  // MARK: - Sheet

  private func setupSheet() {
    // The card is the ONLY opaque element. Everything above it stays clear so
    // the system's dimmed host snapshot shows through (the Voicepop look).
    sheet = ResultSheetView()
    sheet.translatesAutoresizingMaskIntoConstraints = false
    sheet.onClose = { [weak self] in self?.close() }
    sheet.onCopy = { [weak self] text in self?.copyToClipboard(text) }
    sheet.onOpenInApp = { [weak self] in self?.openInApp() }
    sheet.onUpgrade = { [weak self] in self?.upgradeToServer() }
    sheet.onTranslate = { [weak self] in self?.translate() }
    view.addSubview(sheet)
    NSLayoutConstraint.activate([
      sheet.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      sheet.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      sheet.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      sheet.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
    ])

    // Tap on the clear area above the card dismisses, like tapping the dim.
    let tap = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped(_:)))
    tap.cancelsTouchesInView = false
    view.addGestureRecognizer(tap)
  }

  @objc private func backgroundTapped(_ g: UITapGestureRecognizer) {
    let pt = g.location(in: view)
    if !sheet.frame.contains(pt) { close() }
  }

  // MARK: - Input handling

  private static let audioExtensions: Set<String> = [
    "mp3", "m4a", "wav", "ogg", "flac", "aac", "wma", "opus",
    "mp4", "webm", "3gp", "3gpp", "amr", "caf", "aiff",
  ]

  private func handleSharedAudio() {
    guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
      showError("لم يتم العثور على ملف صوتي."); return
    }
    for item in extensionItems {
      guard let attachments = item.attachments else { continue }
      for attachment in attachments {
        if attachment.hasItemConformingToTypeIdentifier(UTType.audio.identifier) ||
           attachment.hasItemConformingToTypeIdentifier("public.audio") ||
           attachment.hasItemConformingToTypeIdentifier("com.apple.m4a-audio") ||
           attachment.hasItemConformingToTypeIdentifier("public.mp3") ||
           attachment.hasItemConformingToTypeIdentifier("public.mpeg-4-audio") ||
           attachment.hasItemConformingToTypeIdentifier("org.xiph.ogg") ||
           attachment.hasItemConformingToTypeIdentifier("org.xiph.opus") {
          loadAttachment(attachment, typeId: UTType.audio.identifier)
          return
        }
        if attachment.hasItemConformingToTypeIdentifier(UTType.movie.identifier) ||
           attachment.hasItemConformingToTypeIdentifier("public.mpeg-4") {
          loadAttachment(attachment, typeId: UTType.movie.identifier)
          return
        }
        if attachment.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
          loadAttachment(attachment, typeId: UTType.fileURL.identifier)
          return
        }
      }
    }
    showError("لم يتم العثور على ملف صوتي مدعوم.")
  }

  private func loadAttachment(_ attachment: NSItemProvider, typeId: String) {
    attachment.loadItem(forTypeIdentifier: typeId, options: nil) { [weak self] (data, error) in
      guard let self = self else { return }
      if let error = error {
        diag("load", "error: \(error.localizedDescription)")
        self.showError("تعذّر قراءة الملف الصوتي.")
        return
      }
      guard let url = data as? URL else {
        self.showError("تنسيق المشاركة غير مدعوم.")
        return
      }
      let ext = url.pathExtension.lowercased()
      guard Self.audioExtensions.contains(ext) else {
        diag("load", "unsupported ext=\(ext)")
        self.showError("نوع الملف غير مدعوم.")
        return
      }
      self.saveToAppGroup(url: url)
    }
  }

  /// Copies the shared file into the App Group container (so it survives after
  /// `loadItem`'s temporary URL is reclaimed, and so "فتح في بصوتك" can hand it
  /// to the app), then kicks off transcription.
  private func saveToAppGroup(url: URL) {
    guard let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id) else {
      diag("save", "containerURL nil — App Group inaccessible")
      showError("تعذّر الوصول إلى مساحة التخزين المشتركة."); return
    }
    detectedExtension = url.pathExtension.isEmpty ? "m4a" : url.pathExtension.lowercased()
    let dest = containerURL.appendingPathComponent(
      "shared_audio_\(Int(Date().timeIntervalSince1970)).\(detectedExtension)")
    do {
      if FileManager.default.fileExists(atPath: dest.path) {
        try FileManager.default.removeItem(at: dest)
      }
      try FileManager.default.copyItem(at: url, to: dest)
      savedAudioPath = dest.path
      diag("save", "✓ copied \(dest.lastPathComponent)")
      transcribe(fileURL: dest)
    } catch {
      diag("save", "copy error: \(error.localizedDescription)")
      showError("تعذّر حفظ الملف الصوتي.")
    }
  }

  // MARK: - Transcription pipeline

  private func transcribe(fileURL: URL) {
    DispatchQueue.main.async { self.sheet.showLoading() }
    // Pick a recognizer locale from the device's preferred languages, biased
    // to Arabic/English which cover the vast majority of our users.
    let locale = Self.preferredLocale()
    OnDeviceSTT.recognize(fileURL: fileURL, locale: locale) { [weak self] result in
      guard let self = self else { return }
      switch result {
      case .success(let text, let confidence):
        diag("stt", "on-device ✓ conf=\(confidence) chars=\(text.count)")
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          // Empty on-device result → try the server instead of showing nothing.
          self.serverFallback(fileURL: fileURL)
        } else {
          let lang = locale.languageCode ?? "ar"
          self.queueClientLog(text: text, lang: lang, fileURL: fileURL)
          DispatchQueue.main.async {
            self.sheet.showResult(
              text: text,
              lang: lang,
              langName: Self.langName(lang),
              wordCount: Self.wordCount(text),
              durationSeconds: Self.audioDuration(fileURL),
              requestId: nil,         // on-device; request id arrives async (logged in app)
              onDevice: true)
          }
        }
      case .failure(let reason):
        diag("stt", "on-device ✗ \(reason) → server fallback")
        self.serverFallback(fileURL: fileURL)
      }
    }
  }

  private func serverFallback(fileURL: URL) {
    guard let token = AppGroup.accessToken() else {
      diag("server", "no token in App Group — cannot fall back")
      DispatchQueue.main.async {
        self.sheet.showResultUnavailable(
          message: "تعذّر التحويل داخل الجهاز. افتح تطبيق بصوتك وسجّل الدخول لإكمال التحويل عبر الخادم.",
          canOpenApp: true)
      }
      return
    }
    ServerTranscriber.transcribe(
      fileURL: fileURL,
      baseUrl: AppGroup.apiBaseUrl(),
      token: token
    ) { [weak self] result in
      guard let self = self else { return }
      switch result {
      case .success(let resp):
        diag("server", "✓ request_id=\(resp.requestId ?? -1)")
        DispatchQueue.main.async {
          self.sheet.showResult(
            text: resp.text,
            lang: resp.lang ?? "ar",
            langName: resp.langName ?? Self.langName(resp.lang ?? "ar"),
            wordCount: resp.wordCount ?? Self.wordCount(resp.text),
            durationSeconds: resp.duration ?? Self.audioDuration(fileURL),
            requestId: resp.requestId,
            onDevice: false)
        }
      case .failure(let message):
        diag("server", "✗ \(message)")
        DispatchQueue.main.async {
          self.sheet.showResultUnavailable(
            message: message, canOpenApp: true)
        }
      }
    }
  }

  /// On-device transcriptions can't reliably reach `/transcriptions/log` from
  /// the extension (the access token may be expired and we can't refresh it
  /// here). Queue the metadata in the App Group; the app flushes the queue on
  /// next launch so history + admin stay complete.
  private func queueClientLog(text: String, lang: String, fileURL: URL) {
    guard let defaults = AppGroup.defaults else { return }
    var queue = defaults.array(forKey: AppGroup.pendingClientLogsKey) as? [[String: Any]] ?? []
    queue.append([
      "text": String(text.prefix(50_000)),
      "lang": lang,
      "duration_seconds": Self.audioDuration(fileURL),
      "source": "share",
      "is_live_recording": false,
      "client_engine": "apple_speech",
    ])
    // Cap the queue so a long offline streak can't grow it unbounded.
    if queue.count > 100 { queue = Array(queue.suffix(100)) }
    defaults.set(queue, forKey: AppGroup.pendingClientLogsKey)
    defaults.synchronize()
  }

  /// User tapped "الحصول على جودة أعلى" on a free on-device result — re-run the
  /// shared file through the server's premium pass (the backend bills it at 2×
  /// the daily quota). Reuses the copy already saved in the App Group container.
  private func upgradeToServer() {
    guard let path = savedAudioPath else {
      showError("تعذّر العثور على الملف الصوتي."); return
    }
    guard let token = AppGroup.accessToken() else {
      DispatchQueue.main.async {
        self.sheet.showResultUnavailable(
          message: "افتح تطبيق بصوتك وسجّل الدخول لإكمال التحويل عبر الخادم.",
          canOpenApp: true)
      }
      return
    }
    let fileURL = URL(fileURLWithPath: path)
    DispatchQueue.main.async {
      self.sheet.showLoading(message: "جاري التحويل عبر الخادم لجودة أعلى…")
    }
    ServerTranscriber.transcribe(
      fileURL: fileURL,
      baseUrl: AppGroup.apiBaseUrl(),
      token: token,
      highQuality: true
    ) { [weak self] result in
      guard let self = self else { return }
      switch result {
      case .success(let resp):
        diag("upgrade", "✓ request_id=\(resp.requestId ?? -1)")
        DispatchQueue.main.async {
          self.sheet.showResult(
            text: resp.text,
            lang: resp.lang ?? "ar",
            langName: resp.langName ?? Self.langName(resp.lang ?? "ar"),
            wordCount: resp.wordCount ?? Self.wordCount(resp.text),
            durationSeconds: resp.duration ?? Self.audioDuration(fileURL),
            requestId: resp.requestId,
            onDevice: false)
        }
      case .failure(let message):
        diag("upgrade", "✗ \(message)")
        DispatchQueue.main.async {
          self.sheet.showResultUnavailable(message: message, canOpenApp: true)
        }
      }
    }
  }

  // MARK: - Actions

  private func copyToClipboard(_ text: String) {
    UIPasteboard.general.string = text
    sheet.flashCopied()
  }

  /// User tapped "ترجمة" — send the transcript to the server translate endpoint
  /// (1 daily credit, charged only on success) and show the Arabic in the sheet.
  private func translate() {
    let text = sheet.translationSourceText
    let lang = sheet.translationSourceLang
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    guard let token = AppGroup.accessToken() else {
      presentTranslateError("افتح تطبيق بصوتك وسجّل الدخول لاستخدام الترجمة.")
      return
    }
    sheet.showTranslating()
    ServerTranscriber.translate(
      text: text,
      sourceLang: lang,
      baseUrl: AppGroup.apiBaseUrl(),
      token: token
    ) { [weak self] result in
      guard let self = self else { return }
      DispatchQueue.main.async {
        switch result {
        case .success(let arabic):
          diag("translate", "✓ chars=\(arabic.count)")
          self.sheet.showTranslation(arabic)
        case .failure(let message):
          diag("translate", "✗ \(message)")
          self.sheet.showTranslateError()
          self.presentTranslateError(message)
        }
      }
    }
  }

  private func presentTranslateError(_ message: String) {
    // Only present if we're on screen and not already presenting — guards
    // against "presentation in progress" / presenting on a dismissing VC.
    guard view.window != nil, presentedViewController == nil else { return }
    let alert = UIAlertController(
      title: "تعذّرت الترجمة", message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "حسناً", style: .default))
    present(alert, animated: true)
  }

  /// Hands the shared file + a deep link to the full app so the user gets the
  /// rich result screen (save, re-share, etc.). Writes the path to the App
  /// Group hand-off slot the SceneDelegate already drains.
  private func openInApp() {
    if let path = savedAudioPath {
      AppGroup.defaults?.set(path, forKey: AppGroup.sharedAudioPathKey)
      AppGroup.defaults?.synchronize()
    }
    let urlScheme = URL(string: "bisawtak://shared")!
    var responder: UIResponder? = self
    while responder != nil {
      if let application = responder as? UIApplication {
        application.open(urlScheme, options: [:], completionHandler: nil)
        break
      }
      responder = responder?.next
    }
    close()
  }

  private func showError(_ message: String) {
    DispatchQueue.main.async {
      self.sheet.showResultUnavailable(message: message, canOpenApp: false)
    }
  }

  private func close() {
    DispatchQueue.main.async {
      self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
  }

  // MARK: - Helpers

  private static func preferredLocale() -> Locale {
    for lang in Locale.preferredLanguages {
      let code = lang.lowercased()
      if code.hasPrefix("ar") { return Locale(identifier: "ar-SA") }
      if code.hasPrefix("en") { return Locale(identifier: "en-US") }
    }
    return Locale(identifier: "ar-SA")
  }

  private static func langName(_ code: String) -> String {
    let c = code.lowercased()
    if c.hasPrefix("ar") { return "العربية" }
    if c.hasPrefix("en") { return "English" }
    if c.hasPrefix("fr") { return "Français" }
    return code
  }

  private static func wordCount(_ text: String) -> Int {
    let parts = text.split { $0 == " " || $0 == "\n" || $0 == "\t" }
    return parts.count
  }

  private static func audioDuration(_ url: URL) -> Double {
    let asset = AVURLAsset(url: url)
    let d = CMTimeGetSeconds(asset.duration)
    return d.isFinite && d > 0 ? d : 0
  }
}
