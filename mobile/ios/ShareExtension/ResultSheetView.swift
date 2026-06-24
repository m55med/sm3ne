import UIKit

/// The floating bottom sheet shown by the Share Extension. Pure UIKit (the
/// extension doesn't host a Flutter engine). RTL-friendly: Arabic is the
/// primary language, so labels read right-to-left and the action row puts the
/// language on the trailing (right) side and "فتح في بصوتك" on the leading
/// (left) side per the product spec.
final class ResultSheetView: UIView {

  var onClose: (() -> Void)?
  var onCopy: ((String) -> Void)?
  var onOpenInApp: (() -> Void)?
  var onUpgrade: (() -> Void)?
  var onTranslate: (() -> Void)?

  private var currentText: String = ""
  private var currentLang: String = ""
  private var currentTranslation: String?

  // Brand tint roughly matching the app's primary.
  private let brand = UIColor(red: 0.20, green: 0.45, blue: 0.95, alpha: 1.0)

  private let container = UIStackView()
  private let bodyScroll = UIScrollView()
  private let textLabel = UILabel()
  private let chipsRow = UIStackView()
  private let actionRow = UIStackView()
  private let copyButton = UIButton(type: .system)
  private let translateButton = UIButton(type: .system)
  private let translateHint = UILabel()
  private let translationCard = UIView()
  private let translationLabel = UILabel()
  private let translationScroll = UIScrollView()
  private let translationCopyButton = UIButton(type: .system)
  private let upgradeButton = UIButton(type: .system)
  private let upgradeNote = UILabel()
  private let openButton = UIButton(type: .system)
  private let langLabel = UILabel()
  private let requestIdLabel = UILabel()
  private let spinner = UIActivityIndicatorView(style: .large)
  private let statusLabel = UILabel()

  override init(frame: CGRect) {
    super.init(frame: frame)
    setup()
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

  private func setup() {
    semanticContentAttribute = .forceRightToLeft
    backgroundColor = .secondarySystemBackground
    layer.cornerRadius = 20
    layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
    layer.masksToBounds = true

    container.axis = .vertical
    container.spacing = 14
    container.translatesAutoresizingMaskIntoConstraints = false
    container.isLayoutMarginsRelativeArrangement = true
    container.directionalLayoutMargins = .init(top: 12, leading: 18, bottom: 24, trailing: 18)
    addSubview(container)
    NSLayoutConstraint.activate([
      container.leadingAnchor.constraint(equalTo: leadingAnchor),
      container.trailingAnchor.constraint(equalTo: trailingAnchor),
      container.topAnchor.constraint(equalTo: topAnchor),
      container.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])

    // Grabber.
    let grabber = UIView()
    grabber.backgroundColor = .tertiaryLabel
    grabber.layer.cornerRadius = 2.5
    grabber.translatesAutoresizingMaskIntoConstraints = false
    grabber.heightAnchor.constraint(equalToConstant: 5).isActive = true
    grabber.widthAnchor.constraint(equalToConstant: 40).isActive = true
    let grabberWrap = UIView()
    grabberWrap.addSubview(grabber)
    grabber.centerXAnchor.constraint(equalTo: grabberWrap.centerXAnchor).isActive = true
    grabber.topAnchor.constraint(equalTo: grabberWrap.topAnchor).isActive = true
    grabber.bottomAnchor.constraint(equalTo: grabberWrap.bottomAnchor).isActive = true
    container.addArrangedSubview(grabberWrap)

    // Header: title + close.
    let header = UIStackView()
    header.axis = .horizontal
    header.alignment = .center
    let title = UILabel()
    title.text = "بصوتك"
    title.font = .systemFont(ofSize: 20, weight: .bold)
    title.textColor = brand
    let closeBtn = UIButton(type: .system)
    closeBtn.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
    closeBtn.tintColor = .tertiaryLabel
    closeBtn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
    header.addArrangedSubview(title)
    header.addArrangedSubview(UIView())   // spacer
    header.addArrangedSubview(closeBtn)
    container.addArrangedSubview(header)

    // Loading state.
    spinner.hidesWhenStopped = true
    statusLabel.font = .systemFont(ofSize: 15)
    statusLabel.textColor = .secondaryLabel
    statusLabel.textAlignment = .center
    statusLabel.numberOfLines = 0
    let loadingStack = UIStackView(arrangedSubviews: [spinner, statusLabel])
    loadingStack.axis = .vertical
    loadingStack.spacing = 12
    loadingStack.alignment = .center
    container.addArrangedSubview(loadingStack)

    // Chips (accuracy/duration + word count).
    chipsRow.axis = .horizontal
    chipsRow.spacing = 8
    chipsRow.alignment = .center
    container.addArrangedSubview(chipsRow)

    // Body text.
    textLabel.font = .systemFont(ofSize: 17)
    textLabel.numberOfLines = 0
    textLabel.textAlignment = .natural
    bodyScroll.translatesAutoresizingMaskIntoConstraints = false
    bodyScroll.addSubview(textLabel)
    textLabel.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      textLabel.leadingAnchor.constraint(equalTo: bodyScroll.contentLayoutGuide.leadingAnchor),
      textLabel.trailingAnchor.constraint(equalTo: bodyScroll.contentLayoutGuide.trailingAnchor),
      textLabel.topAnchor.constraint(equalTo: bodyScroll.contentLayoutGuide.topAnchor),
      textLabel.bottomAnchor.constraint(equalTo: bodyScroll.contentLayoutGuide.bottomAnchor),
      textLabel.widthAnchor.constraint(equalTo: bodyScroll.frameLayoutGuide.widthAnchor),
      bodyScroll.heightAnchor.constraint(lessThanOrEqualToConstant: 220),
    ])
    let bodyCard = UIView()
    bodyCard.backgroundColor = .tertiarySystemBackground
    bodyCard.layer.cornerRadius = 12
    bodyCard.addSubview(bodyScroll)
    NSLayoutConstraint.activate([
      bodyScroll.leadingAnchor.constraint(equalTo: bodyCard.leadingAnchor, constant: 12),
      bodyScroll.trailingAnchor.constraint(equalTo: bodyCard.trailingAnchor, constant: -12),
      bodyScroll.topAnchor.constraint(equalTo: bodyCard.topAnchor, constant: 12),
      bodyScroll.bottomAnchor.constraint(equalTo: bodyCard.bottomAnchor, constant: -12),
    ])
    container.addArrangedSubview(bodyCard)

    // Copy button (full width).
    copyButton.setTitle("نسخ", for: .normal)
    copyButton.setImage(UIImage(systemName: "doc.on.doc"), for: .normal)
    copyButton.tintColor = .white
    copyButton.setTitleColor(.white, for: .normal)
    copyButton.backgroundColor = brand
    copyButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
    copyButton.layer.cornerRadius = 12
    copyButton.heightAnchor.constraint(equalToConstant: 48).isActive = true
    copyButton.addTarget(self, action: #selector(copyTapped), for: .touchUpInside)
    container.addArrangedSubview(copyButton)

    // Translate-to-Arabic button (hidden when the transcript is already Arabic).
    translateButton.setTitle("ترجمة إلى العربية", for: .normal)
    translateButton.setImage(UIImage(systemName: "globe"), for: .normal)
    translateButton.tintColor = brand
    translateButton.setTitleColor(brand, for: .normal)
    translateButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
    translateButton.backgroundColor = brand.withAlphaComponent(0.10)
    translateButton.layer.cornerRadius = 12
    translateButton.layer.borderWidth = 1
    translateButton.layer.borderColor = brand.withAlphaComponent(0.35).cgColor
    translateButton.heightAnchor.constraint(equalToConstant: 46).isActive = true
    translateButton.addTarget(self, action: #selector(translateTapped), for: .touchUpInside)
    container.addArrangedSubview(translateButton)

    translateHint.text = "الترجمة إلى العربية تخصم 1 من رصيدك اليومي"
    translateHint.font = .systemFont(ofSize: 11)
    translateHint.textColor = .secondaryLabel
    translateHint.textAlignment = .center
    translateHint.numberOfLines = 0
    container.addArrangedSubview(translateHint)

    setupTranslationCard()
    container.addArrangedSubview(translationCard)

    // "Higher quality" upgrade — only shown for a free on-device result. A
    // bordered secondary button + a small note that it re-runs via the server
    // and costs 2× the daily quota.
    upgradeButton.setTitle("الحصول على جودة أعلى", for: .normal)
    upgradeButton.setImage(UIImage(systemName: "sparkles"), for: .normal)
    upgradeButton.tintColor = brand
    upgradeButton.setTitleColor(brand, for: .normal)
    upgradeButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
    upgradeButton.backgroundColor = brand.withAlphaComponent(0.10)
    upgradeButton.layer.cornerRadius = 12
    upgradeButton.layer.borderWidth = 1
    upgradeButton.layer.borderColor = brand.withAlphaComponent(0.35).cgColor
    upgradeButton.heightAnchor.constraint(equalToConstant: 46).isActive = true
    upgradeButton.addTarget(self, action: #selector(upgradeTapped), for: .touchUpInside)
    container.addArrangedSubview(upgradeButton)

    upgradeNote.text = "يحوّل الصوت عبر الخادم — يستهلك ٢× من رصيدك اليومي"
    upgradeNote.font = .systemFont(ofSize: 11)
    upgradeNote.textColor = .secondaryLabel
    upgradeNote.textAlignment = .center
    upgradeNote.numberOfLines = 0
    container.addArrangedSubview(upgradeNote)

    // Action row: language (trailing/right) + open-in-app (leading/left).
    openButton.setTitle("فتح في بصوتك", for: .normal)
    openButton.setImage(UIImage(systemName: "arrow.up.forward.app"), for: .normal)
    openButton.tintColor = brand
    openButton.setTitleColor(brand, for: .normal)
    openButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
    openButton.addTarget(self, action: #selector(openTapped), for: .touchUpInside)

    langLabel.font = .systemFont(ofSize: 14, weight: .medium)
    langLabel.textColor = .secondaryLabel
    langLabel.textAlignment = .right

    actionRow.axis = .horizontal
    actionRow.alignment = .center
    actionRow.addArrangedSubview(openButton)   // leading = left
    actionRow.addArrangedSubview(UIView())     // spacer
    actionRow.addArrangedSubview(langLabel)    // trailing = right
    container.addArrangedSubview(actionRow)

    // Request id, small + muted.
    requestIdLabel.font = .systemFont(ofSize: 12)
    requestIdLabel.textColor = .tertiaryLabel
    requestIdLabel.textAlignment = .center
    container.addArrangedSubview(requestIdLabel)

    setResultHidden(true)
  }

  private func setupTranslationCard() {
    translationCard.backgroundColor = brand.withAlphaComponent(0.10)
    translationCard.layer.cornerRadius = 12
    translationCard.layer.borderWidth = 1
    translationCard.layer.borderColor = brand.withAlphaComponent(0.25).cgColor
    translationCard.isHidden = true

    let inner = UIStackView()
    inner.axis = .vertical
    inner.spacing = 6
    inner.translatesAutoresizingMaskIntoConstraints = false
    inner.isLayoutMarginsRelativeArrangement = true
    inner.directionalLayoutMargins = .init(top: 10, leading: 12, bottom: 10, trailing: 12)
    translationCard.addSubview(inner)
    NSLayoutConstraint.activate([
      inner.leadingAnchor.constraint(equalTo: translationCard.leadingAnchor),
      inner.trailingAnchor.constraint(equalTo: translationCard.trailingAnchor),
      inner.topAnchor.constraint(equalTo: translationCard.topAnchor),
      inner.bottomAnchor.constraint(equalTo: translationCard.bottomAnchor),
    ])

    // Header: globe + title + copy-translation.
    let header = UIStackView()
    header.axis = .horizontal
    header.alignment = .center
    header.spacing = 6
    let iv = UIImageView(image: UIImage(systemName: "globe"))
    iv.tintColor = brand
    iv.contentMode = .scaleAspectFit
    iv.widthAnchor.constraint(equalToConstant: 16).isActive = true
    iv.heightAnchor.constraint(equalToConstant: 16).isActive = true
    let title = UILabel()
    title.text = "الترجمة (العربية)"
    title.font = .systemFont(ofSize: 14, weight: .bold)
    title.textColor = brand
    translationCopyButton.setImage(UIImage(systemName: "doc.on.doc"), for: .normal)
    translationCopyButton.tintColor = brand
    translationCopyButton.addTarget(self, action: #selector(copyTranslationTapped), for: .touchUpInside)
    header.addArrangedSubview(iv)
    header.addArrangedSubview(title)
    header.addArrangedSubview(UIView())   // spacer
    header.addArrangedSubview(translationCopyButton)
    inner.addArrangedSubview(header)

    // Body: RTL Arabic text, scrollable.
    translationLabel.font = .systemFont(ofSize: 16)
    translationLabel.numberOfLines = 0
    translationLabel.textAlignment = .right
    translationScroll.translatesAutoresizingMaskIntoConstraints = false
    translationScroll.addSubview(translationLabel)
    translationLabel.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      translationLabel.leadingAnchor.constraint(equalTo: translationScroll.contentLayoutGuide.leadingAnchor),
      translationLabel.trailingAnchor.constraint(equalTo: translationScroll.contentLayoutGuide.trailingAnchor),
      translationLabel.topAnchor.constraint(equalTo: translationScroll.contentLayoutGuide.topAnchor),
      translationLabel.bottomAnchor.constraint(equalTo: translationScroll.contentLayoutGuide.bottomAnchor),
      translationLabel.widthAnchor.constraint(equalTo: translationScroll.frameLayoutGuide.widthAnchor),
      translationScroll.heightAnchor.constraint(lessThanOrEqualToConstant: 180),
    ])
    inner.addArrangedSubview(translationScroll)
  }

  // MARK: - Translation

  /// Resets translation chrome for a fresh result. The translate button is
  /// hidden when the transcript is already Arabic (or empty).
  private func resetTranslation(lang: String) {
    currentLang = lang
    currentTranslation = nil
    let isArabic = lang.lowercased().hasPrefix("ar")
    let hasText = !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let canTranslate = !isArabic && hasText
    translateButton.isHidden = !canTranslate
    translateButton.isEnabled = true
    translateButton.setTitle("ترجمة إلى العربية", for: .normal)
    translateHint.isHidden = !canTranslate
    translationCard.isHidden = true
    translationLabel.text = nil
  }

  func showTranslating() {
    translateButton.isEnabled = false
    translateButton.setTitle("جاري الترجمة…", for: .normal)
  }

  func showTranslation(_ text: String) {
    currentTranslation = text
    translationLabel.text = text
    translationCard.isHidden = false
    translateHint.isHidden = true
    translateButton.isEnabled = true
    translateButton.setTitle("إخفاء الترجمة", for: .normal)
  }

  func showTranslateError() {
    translateButton.isEnabled = true
    translateButton.setTitle("ترجمة إلى العربية", for: .normal)
  }

  /// The transcript text + detected language the controller sends to the
  /// translate endpoint.
  var translationSourceText: String { currentText }
  var translationSourceLang: String { currentLang }

  // MARK: - States

  func showLoading(message: String = "جاري تحويل الصوت...") {
    setResultHidden(true)
    spinner.superview?.isHidden = false
    spinner.startAnimating()
    statusLabel.text = message
  }

  func showResult(
    text: String,
    lang: String,
    langName: String,
    wordCount: Int,
    durationSeconds: Double,
    requestId: Int?,
    onDevice: Bool
  ) {
    currentText = text
    spinner.stopAnimating()
    spinner.superview?.isHidden = true
    setResultHidden(false)

    textLabel.text = text
    langLabel.text = langName
    // Translate button visibility depends on the detected language.
    resetTranslation(lang: lang)

    // Chips: duration + word count.
    chipsRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
    chipsRow.addArrangedSubview(makeChip(
      icon: "clock", text: "\(formatDuration(durationSeconds))"))
    chipsRow.addArrangedSubview(makeChip(
      icon: "text.word.spacing", text: "\(wordCount) كلمة"))
    chipsRow.addArrangedSubview(makeChip(
      icon: onDevice ? "iphone" : "cloud",
      text: onDevice ? "داخل الجهاز" : "عبر الخادم",
      tint: onDevice ? .systemGreen : brand))
    chipsRow.addArrangedSubview(UIView())   // trailing spacer

    if let id = requestId {
      requestIdLabel.text = "معرّف الطلب: #\(id)"
      requestIdLabel.isHidden = false
    } else {
      // On-device rows get their request id assigned when the app flushes the
      // queued log; we don't have it here yet.
      requestIdLabel.text = "سيظهر معرّف الطلب بعد المزامنة"
      requestIdLabel.isHidden = false
    }

    // Offer "higher quality" only for a free on-device result. A server result
    // is already the high-quality path, so re-running it would just waste quota.
    upgradeButton.isEnabled = true
    upgradeButton.isHidden = !onDevice
    upgradeNote.isHidden = !onDevice
  }

  /// Shown when neither on-device nor the server could produce a result.
  func showResultUnavailable(message: String, canOpenApp: Bool) {
    spinner.stopAnimating()
    spinner.superview?.isHidden = true
    setResultHidden(true)
    statusLabel.text = message
    statusLabel.superview?.isHidden = false
    // Clear any leftover result chrome so a prior success can't leak stale
    // language/request-id text into the error state.
    langLabel.text = nil
    requestIdLabel.text = nil
    openButton.isHidden = !canOpenApp
    actionRow.isHidden = !canOpenApp
  }

  func flashCopied() {
    let original = copyButton.title(for: .normal)
    copyButton.setTitle("تم النسخ ✓", for: .normal)
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
      self?.copyButton.setTitle(original, for: .normal)
    }
  }

  // MARK: - Helpers

  private func setResultHidden(_ hidden: Bool) {
    chipsRow.isHidden = hidden
    bodyScroll.superview?.isHidden = hidden
    copyButton.isHidden = hidden
    upgradeButton.isHidden = hidden
    upgradeNote.isHidden = hidden
    actionRow.isHidden = hidden
    requestIdLabel.isHidden = hidden
    // Translation chrome is otherwise driven by resetTranslation/showTranslation
    // (called from showResult); ensure it's hidden whenever there's no result.
    if hidden {
      translateButton.isHidden = true
      translateHint.isHidden = true
      translationCard.isHidden = true
    }
  }

  private func makeChip(icon: String, text: String, tint: UIColor = .secondaryLabel) -> UIView {
    let stack = UIStackView()
    stack.axis = .horizontal
    stack.spacing = 4
    stack.alignment = .center
    stack.isLayoutMarginsRelativeArrangement = true
    stack.directionalLayoutMargins = .init(top: 6, leading: 10, bottom: 6, trailing: 10)
    stack.backgroundColor = tint.withAlphaComponent(0.12)
    stack.layer.cornerRadius = 12
    let iv = UIImageView(image: UIImage(systemName: icon))
    iv.tintColor = tint
    iv.contentMode = .scaleAspectFit
    iv.widthAnchor.constraint(equalToConstant: 14).isActive = true
    iv.heightAnchor.constraint(equalToConstant: 14).isActive = true
    let lbl = UILabel()
    lbl.text = text
    lbl.font = .systemFont(ofSize: 13, weight: .medium)
    lbl.textColor = tint
    stack.addArrangedSubview(iv)
    stack.addArrangedSubview(lbl)
    return stack
  }

  private func formatDuration(_ seconds: Double) -> String {
    if seconds <= 0 { return "—" }
    if seconds < 60 { return "\(Int(seconds.rounded())) ثانية" }
    let m = Int(seconds) / 60
    let s = Int(seconds) % 60
    return "\(m):\(String(format: "%02d", s)) دقيقة"
  }

  @objc private func closeTapped() { onClose?() }
  @objc private func copyTapped() { onCopy?(currentText) }
  @objc private func openTapped() { onOpenInApp?() }
  @objc private func upgradeTapped() {
    // Guard against double-taps while the server pass is in flight.
    upgradeButton.isEnabled = false
    onUpgrade?()
  }

  @objc private func translateTapped() {
    if currentTranslation != nil {
      // Already translated — just toggle the card's visibility.
      let willHide = !translationCard.isHidden
      translationCard.isHidden = willHide
      translateButton.setTitle(willHide ? "إظهار الترجمة" : "إخفاء الترجمة", for: .normal)
    } else {
      onTranslate?()
    }
  }

  @objc private func copyTranslationTapped() {
    if let t = currentTranslation { onCopy?(t) }
  }
}
