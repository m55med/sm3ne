import UIKit
import Social
import MobileCoreServices
import UniformTypeIdentifiers

// TEMPORARY remote diag for the share extension. Helps us see, from the
// device, whether the extension is firing and what UTI it's getting. Remove
// once the share-intent bug is closed.
fileprivate func diag(_ tag: String, _ message: String) {
  NSLog("[DIAG \(tag)] \(message)")
  var req = URLRequest(
    url: URL(string: "https://voice.neojeen.com/api/v1/diag/log")!,
    timeoutInterval: 4
  )
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

class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        diag("life", "viewDidLoad")
        handleSharedAudio()
    }

    private func handleSharedAudio() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            close()
            return
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
                    attachment.loadItem(forTypeIdentifier: UTType.audio.identifier, options: nil) { [weak self] (data, error) in
                        guard error == nil else {
                            self?.close()
                            return
                        }
                        if let url = data as? URL {
                            self?.saveAndRedirect(url: url)
                        }
                    }
                    return
                }
                // Voice notes wrapped in a movie container (Messenger, iOS-recorded m4a/mp4).
                if attachment.hasItemConformingToTypeIdentifier(UTType.movie.identifier) ||
                   attachment.hasItemConformingToTypeIdentifier("public.mpeg-4") {
                    attachment.loadItem(forTypeIdentifier: UTType.movie.identifier, options: nil) { [weak self] (data, error) in
                        guard error == nil, let url = data as? URL else {
                            self?.close()
                            return
                        }
                        if Self.audioExtensions.contains(url.pathExtension.lowercased()) {
                            self?.saveAndRedirect(url: url)
                        } else {
                            self?.close()
                        }
                    }
                    return
                }
                // Generic file URL — pick it up if the extension is one we accept.
                if attachment.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    attachment.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] (data, error) in
                        guard error == nil, let url = data as? URL else {
                            self?.close()
                            return
                        }
                        if Self.audioExtensions.contains(url.pathExtension.lowercased()) {
                            self?.saveAndRedirect(url: url)
                        } else {
                            self?.close()
                        }
                    }
                    return
                }
            }
        }
        close()
    }

    private static let audioExtensions: Set<String> = [
        "mp3", "m4a", "wav", "ogg", "flac", "aac", "wma", "opus",
        "mp4", "webm", "3gp", "3gpp",
    ]

    private func saveAndRedirect(url: URL) {
        diag("save", "input url=\(url.lastPathComponent) ext=\(url.pathExtension)")
        // Copy to shared App Group container
        let groupID = "group.com.bisawtak.bisawtak"
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else {
            diag("save", "containerURL nil — App Group not accessible from extension!")
            close()
            return
        }

        let destURL = containerURL.appendingPathComponent("shared_audio_\(Int(Date().timeIntervalSince1970)).\(url.pathExtension)")

        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: url, to: destURL)
            diag("save", "✓ copied to App Group: \(destURL.lastPathComponent)")

            // Save path to UserDefaults for the main app to pick up
            let userDefaults = UserDefaults(suiteName: groupID)
            if userDefaults == nil {
                diag("save", "UserDefaults(suiteName:) nil!")
            }
            userDefaults?.set(destURL.path, forKey: "shared_audio_path")
            userDefaults?.synchronize()
            diag("save", "✓ wrote shared_audio_path to App Group")

            // Open main app
            let urlScheme = URL(string: "bisawtak://shared")!
            var responder: UIResponder? = self
            var opened = false
            while responder != nil {
                if let application = responder as? UIApplication {
                    application.open(urlScheme, options: [:], completionHandler: nil)
                    opened = true
                    break
                }
                responder = responder?.next
            }
            diag("save", "responder-open attempted opened=\(opened)")
        } catch {
            diag("save", "copy error: \(error.localizedDescription)")
        }

        close()
    }

    private func close() {
        DispatchQueue.main.async {
            self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }
}
