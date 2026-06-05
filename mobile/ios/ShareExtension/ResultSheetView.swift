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

  private var currentText: String = ""

  // Brand tint roughly matching the app's primary.
  private let brand = UIColor(red: 0.20, green: 0.45, blue: 0.95, alpha: 1.0)

  private let container = UIStackView()
  private let bodyScroll = UIScrollView()
  private let textLabel = UILabel()
  private let chipsRow = UIStackView()
  private let actionRow = UIStackView()
  private let copyButton = UIButton(type: .system)
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

  // MARK: - States

  func showLoading(message: String = "جاري تحويل الصوت...") {
    setResultHidden(true)
    spinner.superview?.isHidden = false
    spinner.startAnimating()
    statusLabel.text = message
  }

  func showResult(
    text: String,
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
}
