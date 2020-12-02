import UIKit

public enum SheetSize {
  case fixed(CGFloat)
  case halfScreen
  case fullScreen
}

class InitialTouchPanGestureRecognizer: UIPanGestureRecognizer {
  var initialTouchLocation: CGPoint?

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    super.touchesBegan(touches, with: event)
    initialTouchLocation = touches.first?.location(in: view)
  }
}

public class HSBottomSheet: UIViewController {
  // MARK: - Public Properties
  public private(set) var childViewController: UIViewController

  public let containerView = UIView()
  /// The view that can be pulled to resize a sheeet. This includes the background. To change the color of the bar, use `handleView` instead
  public let pullBarView = UIView()
  public let handleView = UIView()
  public var handleColor: UIColor = UIColor(white: 0.868, alpha: 1) {
    didSet {
      handleView.backgroundColor = handleColor
    }
  }
  public var handleSize: CGSize = CGSize(width: 50, height: 6)
  public var handleTopEdgeInset: CGFloat = 8
  public var handleBottomEdgeInset: CGFloat = 8
  public var animationDuration: Double = 0.2

  public var dismissOnBackgroundTap: Bool = true
  public var dismissOnPan: Bool = true
  public var dismissable: Bool = true {
    didSet {
      guard isViewLoaded else { return }
    }
  }

  public var extendBackgroundBehindHandle: Bool = false {
    didSet {
      guard isViewLoaded else { return }
      pullBarView.backgroundColor = extendBackgroundBehindHandle ? childViewController.view.backgroundColor : .clear
      updateRoundedCorners()
    }
  }

  private var firstPanPoint: CGPoint = .zero

  public var adjustForBottomSafeArea: Bool = false
  public var blurBottomSafeArea: Bool = true
  public var topCornersRadius: CGFloat = 3 {
    didSet {
      guard isViewLoaded else { return }
      updateRoundedCorners()
    }
  }
  public var overlayColor: UIColor = UIColor(white: 0, alpha: 0.7) {
    didSet {
      if isViewLoaded && view?.window != nil {
        view.backgroundColor = overlayColor
      }
    }
  }

  public var willDismiss: ((HSBottomSheet) -> Void)?
  public var didDismiss: ((HSBottomSheet) -> Void)?

  // MARK: - Private properties
  private var containerSize: SheetSize = .fixed(300)
  private var actualContainerSize: SheetSize = .fixed(300)
  private var orderedSheetSizes: [SheetSize] = [.fixed(300), .fullScreen]

  private var panGestureRecognizer: InitialTouchPanGestureRecognizer?
  private weak var childScrollView: UIScrollView?

  private var containerHeightConstraint: NSLayoutConstraint?
  private var containerBottomConstraint: NSLayoutConstraint?
  private var keyboardHeight: CGFloat = 0

  private var safeAreaInsets: UIEdgeInsets {
    var insets = UIEdgeInsets.zero
    if #available(iOS 11.0, *) {
      insets = UIApplication.shared.keyWindow?.safeAreaInsets ?? insets
    }
    insets.top = max(insets.top, 24)
    return insets
  }

  // MARK: - Functions
  @available(*, deprecated, message: "Use the init(controller:, sizes:) initializer")
  public required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
    childViewController = UIViewController()
    super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
  }

  public convenience init(controller: UIViewController, sizes: [SheetSize] = []) {
    self.init(nibName: nil, bundle: nil)
    childViewController = controller
    if sizes.count > 0 {
      setSizes(sizes, animated: false)
    }
    modalPresentationStyle = .overFullScreen
  }

  public override func viewDidLoad() {
    super.viewDidLoad()

    view.backgroundColor = UIColor.clear
    setUpContainerView()

    if (dismissable) {
      setUpDismissView()

      let panGestureRecognizer = InitialTouchPanGestureRecognizer(target: self,
                                                                  action: #selector(panned(_:)))
      view.addGestureRecognizer(panGestureRecognizer)
      panGestureRecognizer.delegate = self
      self.panGestureRecognizer = panGestureRecognizer
    }

    setUpChildViewController()
    setUpPullBarView()
    updateRoundedCorners()
    NotificationCenter.default.addObserver(
      self, selector: #selector(keyboardShown(_:)),
      name: UIResponder.keyboardWillChangeFrameNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(keyboardDismissed(_:)),
      name: UIResponder.keyboardWillHideNotification,
      object: nil
    )
  }

  public override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    UIView.animate(
      withDuration: animationDuration,
      delay: 0,
      options: [.curveEaseOut],
      animations: { [weak self] in
        guard let `self` = self else { return }
        self.view.backgroundColor = self.overlayColor
        self.containerView.transform = CGAffineTransform.identity
        self.actualContainerSize = .fixed(self.containerView.frame.height)
      },
      completion: nil
    )
  }

  public func setSizes(_ sizes: [SheetSize], animated: Bool = true) {
    guard sizes.count > 0 else {
      return
    }
    orderedSheetSizes = sizes
      .sorted { self.height(for: $0) < self.height(for: $1) }

    resize(to: sizes[0], animated: animated)
  }

  public func resize(to size: SheetSize, animated: Bool = true) {
    if animated {
      UIView.animate(
        withDuration: 0.2,
        delay: 0,
        options: [.curveEaseOut],
        animations: { [weak self] in
          guard let `self` = self, let constraint = self.containerHeightConstraint else { return }
          constraint.constant = self.height(for: size)
          self.view.layoutIfNeeded()
        },
        completion: nil
      )
    } else {
      containerHeightConstraint?.constant = self.height(for: size)
    }
    containerSize = size
    actualContainerSize = size
  }

  private func updateLegacyRoundedCorners() {
    if #available(iOS 11.0, *) {
      childViewController
        .view
        .layer
        .maskedCorners = [.layerMaxXMinYCorner, .layerMinXMinYCorner]
      return
    }
    let path = UIBezierPath(
      roundedRect: childViewController.view.bounds,
      byRoundingCorners: [.topLeft, .topRight],
      cornerRadii: CGSize(width: 10, height: 10)
    )
    let maskLayer = CAShapeLayer()
    maskLayer.path = path.cgPath
    childViewController.view.layer.mask = maskLayer
  }

  private func setUpOverlay() {
    let overlay = UIView(frame: CGRect.zero)
    overlay.backgroundColor = overlayColor
    view.addSubview(overlay)
    var constraints: [NSLayoutConstraint] = []
    let layout = ["H:|[overlay]|",
                  "V:|[overlay]|"]
    layout.forEach {
      constraints += NSLayoutConstraint.constraints(
        withVisualFormat: $0,
        options: [],
        metrics: nil,
        views: ["overlay": overlay]
      )
    }
    NSLayoutConstraint.activate(constraints)
  }

  private func setUpContainerView() {
    containerView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(containerView)
    containerBottomConstraint = containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    containerBottomConstraint?.isActive = true
    containerHeightConstraint = containerView.heightAnchor.constraint(equalToConstant: height(for: containerSize))
    containerHeightConstraint?.priority = UILayoutPriority(900)
    containerHeightConstraint?.isActive = true
    NSLayoutConstraint.activate([
      containerView.leftAnchor.constraint(equalTo: view.leftAnchor),
      containerView.rightAnchor.constraint(equalTo: view.rightAnchor),
      containerView.topAnchor.constraint(greaterThanOrEqualTo: view.topAnchor, constant: safeAreaInsets.top + 24)
    ])

    containerView.layer.masksToBounds = true
    containerView.backgroundColor = UIColor.clear
    containerView.transform = CGAffineTransform(translationX: 0,
                                                y: UIScreen.main.bounds.height)

    let whiteView = UIView(frame: .zero)
    whiteView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(whiteView)
    let height = whiteView.heightAnchor.constraint(equalToConstant: 0)
    height.priority = UILayoutPriority(100)
    height.isActive = true
    whiteView.backgroundColor = .white
    NSLayoutConstraint.activate([
      whiteView.leftAnchor.constraint(equalTo: view.leftAnchor),
      whiteView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      whiteView.rightAnchor.constraint(equalTo: view.rightAnchor)
    ])
  }

  private func setUpChildViewController() {
    childViewController.willMove(toParent: self)
    addChild(childViewController)
    childViewController.view.translatesAutoresizingMaskIntoConstraints = false
    containerView.addSubview(childViewController.view)
    NSLayoutConstraint.activate([
      childViewController.view.leftAnchor.constraint(equalTo: containerView.leftAnchor),
      childViewController.view.topAnchor.constraint(equalTo: containerView.topAnchor),
      childViewController.view.rightAnchor.constraint(equalTo: containerView.rightAnchor)
    ])

    if adjustForBottomSafeArea {
      childViewController.view.bottomAnchor.constraint(
        equalTo: containerView.bottomAnchor,
        constant: safeAreaInsets.bottom
      ).isActive = true
    } else {
      childViewController.view.bottomAnchor
        .constraint(equalTo: containerView.bottomAnchor).isActive = true
    }

    childViewController.view.layer.masksToBounds = true

    childViewController.didMove(toParent: self)
  }

  private func updateRoundedCorners() {
    if #available(iOS 11.0, *) {
      let controllerWithRoundedCorners = extendBackgroundBehindHandle ? containerView : childViewController.view
      let controllerWithoutRoundedCorners = extendBackgroundBehindHandle ? childViewController.view : containerView
      controllerWithRoundedCorners?.layer.maskedCorners = topCornersRadius > 0 ? [.layerMaxXMinYCorner, .layerMinXMinYCorner] : []
      controllerWithRoundedCorners?.layer.cornerRadius = topCornersRadius
      controllerWithoutRoundedCorners?.layer.maskedCorners = []
      controllerWithoutRoundedCorners?.layer.cornerRadius = 0
    }
  }

  private func setUpDismissView() {
    let dismissAreaView = UIView(frame: CGRect.zero)
    view.addSubview(dismissAreaView)
    view.addSubview(containerView)
    dismissAreaView.translatesAutoresizingMaskIntoConstraints = false
    containerView.translatesAutoresizingMaskIntoConstraints = false

    NSLayoutConstraint.activate([
      dismissAreaView.leftAnchor.constraint(equalTo: view.leftAnchor),
      dismissAreaView.topAnchor.constraint(equalTo: view.topAnchor),
      dismissAreaView.rightAnchor.constraint(equalTo: view.rightAnchor),
      dismissAreaView.bottomAnchor.constraint(equalTo: containerView.topAnchor)
    ])

    dismissAreaView.backgroundColor = UIColor.clear
    dismissAreaView.isUserInteractionEnabled = true

    let tapGestureRecognizer = UITapGestureRecognizer(target: self,
                                                      action: #selector(dismissTapped))
    dismissAreaView.addGestureRecognizer(tapGestureRecognizer)
  }

  private func setUpPullBarView() {
    pullBarView.translatesAutoresizingMaskIntoConstraints = false
    containerView.addSubview(pullBarView)
    NSLayoutConstraint.activate([
      pullBarView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
      pullBarView.topAnchor.constraint(equalTo: containerView.topAnchor),
      pullBarView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor)
    ])

    handleView.translatesAutoresizingMaskIntoConstraints = false
    pullBarView.addSubview(handleView)
    NSLayoutConstraint.activate([
      handleView.centerXAnchor.constraint(equalTo: pullBarView.centerXAnchor),
      handleView.heightAnchor.constraint(equalToConstant: handleSize.height),
      handleView.widthAnchor.constraint(equalToConstant: handleSize.width),
      handleView.topAnchor.constraint(equalTo: pullBarView.topAnchor, constant: handleTopEdgeInset),
      handleView.bottomAnchor.constraint (equalTo: pullBarView.bottomAnchor)
    ])

    pullBarView.layer.masksToBounds = true
    pullBarView.backgroundColor = extendBackgroundBehindHandle ?
      childViewController.view.backgroundColor : UIColor.clear

    handleView.layer.cornerRadius = handleSize.height / 2.0
    handleView.layer.masksToBounds = true
    handleView.backgroundColor = handleColor

    pullBarView.isAccessibilityElement = true
    pullBarView.accessibilityLabel = "Pull bar"
    pullBarView.accessibilityHint = "Tap on this bar to dismiss the modal"
    pullBarView
      .addGestureRecognizer(UITapGestureRecognizer(target: self,
                                                   action: #selector(dismissTapped)))
  }

  @objc func dismissTapped() {
    guard dismissOnBackgroundTap else { return }
    closeSheet()
  }

  public func closeSheet(completion: (() -> Void)? = nil) {
    UIView.animate(
      withDuration: animationDuration,
      delay: 0,
      options: [.curveEaseIn],
      animations: { [weak self] in
        self?
          .containerView
          .transform = CGAffineTransform(translationX: 0,
                                         y: self?.containerView.frame.height ?? 0)
        self?.view.backgroundColor = UIColor.clear
      },
      completion: { [weak self] complete in
        self?.dismiss(animated: false, completion: completion)
      }
    )
  }

  override public func dismiss(
    animated flag: Bool,
    completion: (() -> Void)? = nil
  ) {
    willDismiss?(self)
    super.dismiss(animated: flag) {
      self.didDismiss?(self)
      completion?()
    }
  }

  @objc func panned(_ gesture: UIPanGestureRecognizer) {
    let point = gesture.translation(in: gesture.view?.superview)
    if gesture.state == .began {
      firstPanPoint = point
      actualContainerSize = .fixed(containerView.frame.height)
    }
    
    let minHeight = min(height(for: actualContainerSize), height(for: orderedSheetSizes.first))
    let maxHeight = max(height(for: actualContainerSize), height(for: orderedSheetSizes.last))

    var newHeight = max(0, height(for: actualContainerSize) + (firstPanPoint.y - point.y))
    var offset: CGFloat = 0
    if newHeight < minHeight {
      offset = minHeight - newHeight
      newHeight = minHeight
    }
    if newHeight > maxHeight {
      newHeight = maxHeight
    }

    switch gesture.state {
      case .cancelled, .failed:
        UIView.animate(
          withDuration: animationDuration,
          delay: 0,
          options: [.curveEaseOut],
          animations: {
            self.containerView.transform = CGAffineTransform.identity
            self.containerHeightConstraint?.constant = self.height(for: self.containerSize)
          }
        )
      case .ended:
        let velocity = (0.2 * gesture.velocity(in: self.view).y)
        let finalHeight = velocity > 500 ? -1 : newHeight - offset - velocity
        let animationDuration = TimeInterval(abs(velocity*0.0002) + 0.2)

        guard finalHeight >= (minHeight / 2) || !dismissOnPan else {
          // Dismiss
          UIView.animate(
            withDuration: animationDuration,
            delay: 0,
            options: [.curveEaseOut],
            animations: { [weak self] in
              self?.containerView.transform = CGAffineTransform(
                translationX: 0,
                y: self?.containerView.frame.height ?? 0
              )
              self?.view.backgroundColor = UIColor.clear
            },
            completion: { [weak self] complete in
              self?.dismiss(animated: false, completion: nil)
            }
          )
          return
        }

        if point.y < 0 {
          containerSize = orderedSheetSizes.last ?? containerSize
          orderedSheetSizes.reversed().forEach {
            containerSize = finalHeight < height(for: $0) ? $0 : containerSize
          }
        } else {
          containerSize = orderedSheetSizes.first ?? containerSize
          orderedSheetSizes.forEach {
            containerSize = finalHeight > height(for: $0) ? $0 : containerSize
          }
        }

        UIView.animate(
          withDuration: animationDuration,
          delay: 0,
          options: [.curveEaseOut],
          animations: {
            self.containerView.transform = CGAffineTransform.identity
            self
              .containerHeightConstraint?
              .constant = self.height(for: self.containerSize)
            self.view.layoutIfNeeded()
          },
          completion: { [weak self] complete in
            guard let `self` = self else { return }
            self.actualContainerSize = .fixed(self.containerView.frame.height)
          }
        )
      default:
        containerHeightConstraint?.constant = newHeight
        //      Constraints(for: containerView) { _ in
        //        self.containerHeightConstraint?.constant = newHeight
        //      }
        containerView.transform = offset > 0 && dismissOnPan ?
          CGAffineTransform(translationX: 0, y: offset) : .identity
    }
  }

  @objc func keyboardShown(_ notification: Notification) {
    guard let info = notification.userInfo,
          let keyboardRect = (info[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }

    let windowRect = view.convert(view.bounds, to: nil)
    let actualHeight = windowRect.maxY - keyboardRect.origin.y
    adjustForKeyboard(height: actualHeight, from: notification)
  }

  @objc func keyboardDismissed(_ notification: Notification) {
    adjustForKeyboard(height: 0, from: notification)
  }

  private func adjustForKeyboard(height: CGFloat, from notification: Notification) {
    guard let info = notification.userInfo else { return }
    keyboardHeight = height

    let duration = (info[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0
    let animationCurveRawNSN = info[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber
    let animationCurveRaw = animationCurveRawNSN?.uintValue ?? UIView.AnimationOptions.curveEaseInOut.rawValue
    let animationCurve = UIView.AnimationOptions(rawValue: animationCurveRaw)

    UIView.animate(
      withDuration: duration,
      delay: 0,
      options: animationCurve,
      animations: {
        self.containerBottomConstraint?.constant = min(0, -height + (self.adjustForBottomSafeArea ? self.safeAreaInsets.bottom : 0))
        self.childViewController.view.setNeedsLayout()
        self.view.layoutIfNeeded()
      }
    )
  }

  public func handleScrollView(_ scrollView: UIScrollView) {
    guard let panGestureRecognizer = panGestureRecognizer else { return }
    scrollView.panGestureRecognizer.require(toFail: panGestureRecognizer)
    childScrollView = scrollView
  }

  private func height(for size: SheetSize?) -> CGFloat {
    guard let size = size else { return 0 }
    switch (size) {
      case .fixed(let height):
        return height
      case .fullScreen:
        let insets = self.safeAreaInsets
        return UIScreen.main.bounds.height - insets.top - 24
      case .halfScreen:
        return (UIScreen.main.bounds.height) / 2 + 24
    }
  }
}

extension HSBottomSheet: UIGestureRecognizerDelegate {
  public func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldReceive touch: UITouch
  ) -> Bool {
    guard let view = touch.view else { return true }
    return !(view is UIControl)
  }

  public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    guard
      let panGestureRecognizer = gestureRecognizer as? InitialTouchPanGestureRecognizer,
      let childScrollView = childScrollView,
      let point = panGestureRecognizer.initialTouchLocation
    else { return true }

    let pointInChildScrollView = view.convert(point, to: childScrollView).y - childScrollView.contentOffset.y

    let velocity = panGestureRecognizer.velocity(in: panGestureRecognizer.view?.superview)
    guard pointInChildScrollView > 0, pointInChildScrollView < childScrollView.bounds.height else {
      if keyboardHeight > 0 {
        childScrollView.endEditing(true)
      }
      return true
    }

    guard abs(velocity.y) > abs(velocity.x), childScrollView.contentOffset.y == 0 else { return false }

    if velocity.y < 0 {
      let containerHeight = height(for: containerSize)
      return height(for: orderedSheetSizes.last) > containerHeight && containerHeight < height(for: SheetSize.fullScreen)
    } else {
      return true
    }
  }
}
