import UIKit
import Social
import MobileCoreServices
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
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
        // Copy to shared App Group container
        let groupID = "group.com.bisawtak.bisawtak"
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else {
            close()
            return
        }

        let destURL = containerURL.appendingPathComponent("shared_audio_\(Int(Date().timeIntervalSince1970)).\(url.pathExtension)")

        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: url, to: destURL)

            // Save path to UserDefaults for the main app to pick up
            let userDefaults = UserDefaults(suiteName: groupID)
            userDefaults?.set(destURL.path, forKey: "shared_audio_path")
            userDefaults?.synchronize()

            // Open main app
            let urlScheme = URL(string: "bisawtak://shared")!
            var responder: UIResponder? = self
            while responder != nil {
                if let application = responder as? UIApplication {
                    application.open(urlScheme, options: [:], completionHandler: nil)
                    break
                }
                responder = responder?.next
            }
        } catch {
            print("Error copying file: \(error)")
        }

        close()
    }

    private func close() {
        DispatchQueue.main.async {
            self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }
}
