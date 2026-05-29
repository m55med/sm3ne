import Foundation
import Speech

/// On-device file transcription for the Share Extension, mirroring the main
/// app's `SpeechFileRecognizer` (AppDelegate.swift). Forces on-device
/// recognition so audio never leaves the phone, and surfaces a confidence
/// score so we can fall back to the server on a low-quality result.
///
/// Memory note: app extensions are capped (~120 MB). On-device recognition of
/// a long file can exceed that; if it does, Apple errors out and the caller
/// falls back to the server pipeline, so this stays a safe first attempt.
enum OnDeviceSTT {

  enum Outcome {
    case success(text: String, confidence: Double)
    case failure(reason: String)
  }

  // Keep a strong reference to the in-flight task for the duration of the call.
  private static var activeTask: SFSpeechRecognitionTask?

  static func recognize(
    fileURL: URL,
    locale: Locale,
    completion: @escaping (Outcome) -> Void
  ) {
    SFSpeechRecognizer.requestAuthorization { status in
      DispatchQueue.main.async {
        guard status == .authorized else {
          completion(.failure(reason: "not_authorized:\(status.rawValue)"))
          return
        }
        perform(fileURL: fileURL, locale: locale, completion: completion)
      }
    }
  }

  private static func perform(
    fileURL: URL,
    locale: Locale,
    completion: @escaping (Outcome) -> Void
  ) {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      completion(.failure(reason: "file_not_found")); return
    }
    guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
      completion(.failure(reason: "recognizer_unavailable")); return
    }
    guard recognizer.supportsOnDeviceRecognition else {
      completion(.failure(reason: "no_on_device_support")); return
    }

    let request = SFSpeechURLRecognitionRequest(url: fileURL)
    request.requiresOnDeviceRecognition = true
    request.shouldReportPartialResults = false
    if #available(iOS 16.0, *) { request.addsPunctuation = true }

    var finished = false
    activeTask?.cancel()
    activeTask = recognizer.recognitionTask(with: request) { recognition, error in
      if finished { return }
      if let error = error {
        finished = true
        let ns = error as NSError
        completion(.failure(reason: "task_error:\(ns.domain):\(ns.code)"))
        activeTask = nil
        return
      }
      guard let recognition = recognition else { return }
      if recognition.isFinal {
        finished = true
        let text = recognition.bestTranscription.formattedString
        let segments = recognition.bestTranscription.segments
        let confidence: Double
        if segments.isEmpty {
          confidence = 0
        } else {
          let total = segments.reduce(0.0) { $0 + Double($1.confidence) }
          confidence = total / Double(segments.count)
        }
        completion(.success(text: text, confidence: confidence))
        activeTask = nil
      }
    }
  }
}
