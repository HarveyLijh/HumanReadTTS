import AppKit
import os

private let figureLog = Logger(subsystem: "app.rhea.mac", category: "resizable-figure")

/// File-type sentinel used to look up our view provider class.
/// `ResizableFigureAttachment` returns this from its overridden
/// `fileType` getter; AppKit then resolves it to
/// `ResizableFigureViewProvider` via `registerViewProviderClass`.
let kResizableFigureFileType = "app.rhea.figure"

/// Registers `ResizableFigureViewProvider` so AppKit knows to ask it
/// for views whenever it sees an attachment with our file type. Calling
/// this multiple times is safe — `registerViewProviderClass` overwrites
/// the prior binding for the same fileType.
@MainActor
func registerResizableFigureProvider() {
    NSTextAttachment.registerViewProviderClass(
        ResizableFigureViewProvider.self,
        forFileType: kResizableFigureFileType
    )
}

/// Per-document, session-only cache of figure widths keyed by figure
/// id. Survives re-renders (font scale change, mermaid image resolve)
/// without round-tripping through SwiftUI state, because the renderer
/// reads from it when constructing fresh `ResizableFigureAttachment`s.
///
/// Always accessed on the main thread (AppKit text rendering, SwiftUI
/// state); marked `@unchecked Sendable` so it can be used from the
/// AppKit override methods that are declared nonisolated upstream.
final class FigureWidthCache: @unchecked Sendable {
    var widths: [String: CGFloat] = [:]
}

/// Inline figure attachment that supports hover-driven width resize.
///
/// The renderer emits one of these for every mermaid diagram and every
/// regular markdown image. Width is session-only and stored on the
/// `FigureWidthCache` so subsequent re-renders restore the same size.
///
/// `@unchecked Sendable` because every touch happens on the main thread
/// (AppKit layout, mouse handling); we rely on that convention rather
/// than annotating with `@MainActor`, since the AppKit superclass's
/// overridden methods are nonisolated and incompatible with strict
/// main-actor isolation.
final class ResizableFigureAttachment: NSTextAttachment, @unchecked Sendable {
    /// Stable identity used as the cache key. Mermaid: source hash.
    /// Image: resolved URL string. Persists width across re-renders.
    let figureID: String
    let baselineWidth: CGFloat
    let aspect: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    /// Mutable, session-only width. View provider reads this each time
    /// the layout manager queries `attachmentBounds`.
    var currentWidth: CGFloat
    weak var widthCache: FigureWidthCache?
    /// Resolves the image to draw. The closure dereferences a parent-
    /// owned cache so newly-resolved mermaid diagrams or async-loaded
    /// images replace the placeholder without rebuilding the attachment.
    let imageProvider: () -> NSImage?

    init(
        figureID: String,
        baselineWidth: CGFloat,
        aspect: CGFloat,
        minWidth: CGFloat = 140,
        maxWidth: CGFloat = 720,
        widthCache: FigureWidthCache? = nil,
        imageProvider: @escaping () -> NSImage?
    ) {
        self.figureID = figureID
        self.baselineWidth = baselineWidth
        self.aspect = max(0.1, aspect)
        self.minWidth = minWidth
        self.maxWidth = max(minWidth + 1, maxWidth)
        self.imageProvider = imageProvider
        self.widthCache = widthCache
        let restored = widthCache?.widths[figureID] ?? baselineWidth
        self.currentWidth = max(minWidth, min(maxWidth, restored))
        // The default `init(data:ofType:)` won't make `fileType` stick
        // for our private string — see the `fileType` override below for
        // why we sidestep the inherited storage entirely.
        super.init(data: nil, ofType: nil)
        self.image = imageProvider()
        self.bounds = CGRect(x: 0, y: 0, width: currentWidth, height: currentHeight)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    /// `NSTextAttachment.fileType`'s default setter silently drops the
    /// value when the attachment has no backing UTI-shaped file wrapper,
    /// so the `registerViewProviderClass(forFileType:)` lookup never
    /// finds our provider and TK2 falls back to plain image rendering.
    /// Override with a plain stored property: the lookup is a string
    /// match, not a UTI conformance check, so this is sufficient.
    private var _overriddenFileType: String? = kResizableFigureFileType
    override var fileType: String? {
        get { _overriddenFileType }
        set { _overriddenFileType = newValue }
    }

    var currentHeight: CGFloat { currentWidth / aspect }

    /// Clamps and writes back into the cache. Returns the post-clamp
    /// width so callers can reuse the result without re-clamping.
    @discardableResult
    func setWidth(_ newWidth: CGFloat) -> CGFloat {
        let w = max(minWidth, min(maxWidth, newWidth))
        currentWidth = w
        bounds = CGRect(x: 0, y: 0, width: w, height: w / aspect)
        widthCache?.widths[figureID] = w
        return w
    }

    /// TextKit 1 path falls back to the cached image at the current
    /// width. View provider takes over on TextKit 2.
    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any],
        location: any NSTextLocation,
        textContainer: NSTextContainer?,
        proposedLineFragment: CGRect,
        position: CGPoint
    ) -> CGRect {
        return CGRect(x: 0, y: 0, width: currentWidth, height: currentHeight)
    }
}

/// Hosts the AppKit view that draws the figure plus its hover slider.
/// Lives only on TextKit 2 — TK1 falls back to the attachment's image.
///
/// See `ResizableFigureAttachment` for the `@unchecked Sendable`
/// rationale.
final class ResizableFigureViewProvider: NSTextAttachmentViewProvider, @unchecked Sendable {
    /// Per Apple's forum guidance (FB12061266 / DTS thread 697381),
    /// `tracksTextAttachmentViewBounds` MUST be set inside the
    /// initializer — assigning it after the provider is created leaves
    /// the layout system using the static fallback bounds.
    override init(
        textAttachment: NSTextAttachment,
        parentView: NSView?,
        textLayoutManager: NSTextLayoutManager?,
        location: any NSTextLocation
    ) {
        super.init(
            textAttachment: textAttachment,
            parentView: parentView,
            textLayoutManager: textLayoutManager,
            location: location
        )
        tracksTextAttachmentViewBounds = true
        figureLog.debug("provider init for attachment \(type(of: textAttachment), privacy: .public)")
    }

    override func loadView() {
        guard let attachment = textAttachment as? ResizableFigureAttachment else {
            figureLog.error("loadView called but attachment is \(type(of: self.textAttachment), privacy: .public)")
            super.loadView()
            return
        }
        figureLog.debug("loadView for figure \(attachment.figureID, privacy: .public) w=\(attachment.currentWidth)")
        // AppKit guarantees `loadView` runs on the main thread, but the
        // parent method's nonisolated declaration prevents Swift 6 from
        // inferring main-actor isolation here. The `nonisolated(unsafe)`
        // shim erases isolation tracking for the captured references so
        // we can hop into a main-actor closure to call the NSView-
        // inherited @MainActor initializer of `ResizableFigureView`.
        nonisolated(unsafe) let unsafeAttachment = attachment
        nonisolated(unsafe) let unsafeSelf = self
        MainActor.assumeIsolated {
            unsafeSelf.view = ResizableFigureView(
                attachment: unsafeAttachment,
                provider: unsafeSelf
            )
        }
    }

    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any],
        location: any NSTextLocation,
        textContainer: NSTextContainer?,
        proposedLineFragment: CGRect,
        position: CGPoint
    ) -> CGRect {
        guard let attachment = textAttachment as? ResizableFigureAttachment else {
            return super.attachmentBounds(
                for: attributes,
                location: location,
                textContainer: textContainer,
                proposedLineFragment: proposedLineFragment,
                position: position
            )
        }
        // Cap the max width by the current line-fragment width so a
        // wide figure can't push beyond the column. The slider's own
        // max also tracks this when the user drags toward the right.
        let containerLimit: CGFloat
        if proposedLineFragment.width > 0 {
            containerLimit = proposedLineFragment.width
        } else if let size = textContainer?.size, size.width > 0 {
            containerLimit = size.width
        } else {
            containerLimit = attachment.maxWidth
        }
        let effectiveMax = max(attachment.minWidth + 1, min(attachment.maxWidth, containerLimit))
        if attachment.currentWidth > effectiveMax {
            attachment.currentWidth = effectiveMax
        }
        let w = attachment.currentWidth
        return CGRect(x: 0, y: 0, width: w, height: w / attachment.aspect)
    }
}

// MARK: - View

/// AppKit view that the attachment provider hands to TextKit 2 to draw
/// in place of the attachment glyph. Composes:
///   - an image layer that paints the resolved figure
///   - a slim pill-shaped slider, fading in on hover/drag, that
///     resizes the attachment width interactively
///
/// See `ResizableFigureAttachment` for the `@unchecked Sendable`
/// rationale.
final class ResizableFigureView: NSView, @unchecked Sendable {
    private let attachment: ResizableFigureAttachment
    private weak var provider: ResizableFigureViewProvider?

    private let imageView: NSImageView = {
        let v = NSImageView()
        v.imageScaling = .scaleProportionallyUpOrDown
        v.imageAlignment = .alignCenter
        v.wantsLayer = true
        v.layer?.cornerRadius = 4
        v.layer?.masksToBounds = true
        return v
    }()

    private let slider: FigureSliderView
    private var trackingArea: NSTrackingArea?
    private var hovered = false { didSet { refreshSliderVisibility() } }
    private var dragging = false { didSet { refreshSliderVisibility() } }
    /// Once the user clicks the figure we keep the slider visible until
    /// they click somewhere else. This makes the affordance discoverable
    /// even if the hover-only fade-in is being eaten by the surrounding
    /// NSTextView's tracking machinery.
    private var pinnedOpen = false { didSet { refreshSliderVisibility() } }

    init(attachment: ResizableFigureAttachment, provider: ResizableFigureViewProvider) {
        self.attachment = attachment
        self.provider = provider
        self.slider = FigureSliderView(
            min: attachment.minWidth,
            max: attachment.maxWidth,
            value: attachment.currentWidth,
            columnReference: attachment.maxWidth
        )
        super.init(frame: NSRect(
            x: 0, y: 0,
            width: attachment.currentWidth,
            height: attachment.currentHeight
        ))
        wantsLayer = true
        addSubview(imageView)
        addSubview(slider)
        slider.alphaValue = 0
        slider.onValueChanged = { [weak self] newValue, isFinal in
            self?.handleSliderChange(newValue, isFinal: isFinal)
        }
        slider.onDragStateChanged = { [weak self] active in
            self?.dragging = active
        }
        refreshLayout()
        // Re-pull the image in case the cache resolved between
        // attachment creation and view materialization.
        imageView.image = attachment.imageProvider()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = trackingArea { removeTrackingArea(area) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [
                .mouseEnteredAndExited, .activeInKeyWindow,
                .inVisibleRect, .cursorUpdate
            ],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
        // Cursor rects live on a separate AppKit machinery from
        // tracking areas. Without this, NSTextView's I-beam wins and
        // the user can't tell the figure is interactive.
        discardCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        NSCursor.pointingHand.set()
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        if !pinnedOpen { NSCursor.iBeam.set() }
    }

    /// First click reveals the slider and gives focus to the figure;
    /// subsequent clicks outside the slider's track close it. NSTextView
    /// tries to interpret clicks on attachments as caret placement, so
    /// we eat the mouseDown here unless the click landed on the slider
    /// (the slider itself is a subview that returns non-nil from its
    /// own `hitTest`).
    override func mouseDown(with event: NSEvent) {
        pinnedOpen.toggle()
    }

    /// Forwarded to the figure view itself when no subview claims the
    /// hit. Returning self ensures NSTextView doesn't get the click and
    /// re-route it through caret-placement logic.
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Subviews (slider) get first chance via the standard recursion.
        if let inner = super.hitTest(point) { return inner }
        // Otherwise, if the point is inside us, claim the hit ourselves
        // — this is what stops NSTextView from grabbing the click.
        let local = convert(point, from: superview)
        return bounds.contains(local) ? self : nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // The image cache may have populated after init; pull again
        // any time the view re-attaches (e.g. scrolling back into view).
        imageView.image = attachment.imageProvider()
    }

    override func layout() {
        super.layout()
        refreshLayout()
    }

    private func refreshLayout() {
        imageView.frame = bounds
        let sliderSize = slider.intrinsicContentSize
        let sx = (bounds.width - sliderSize.width) / 2
        let sy = bounds.height - sliderSize.height - 8
        slider.frame = NSRect(
            x: max(8, sx),
            y: max(8, sy),
            width: sliderSize.width,
            height: sliderSize.height
        )
    }

    private func refreshSliderVisibility() {
        let target: CGFloat = (hovered || dragging || pinnedOpen) ? 1 : 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            slider.animator().alphaValue = target
        }
    }

    private func handleSliderChange(_ newValue: CGFloat, isFinal: Bool) {
        let applied = attachment.setWidth(newValue)
        // Resize self so subsequent layout queries see the new size,
        // then ask the layout manager to re-flow this attachment.
        let newSize = NSSize(width: applied, height: applied / attachment.aspect)
        if frame.size != newSize {
            frame.size = newSize
            refreshLayout()
        }
        invalidateAttachmentLayout()
    }

    /// Forces the surrounding text to re-flow around the new figure
    /// size. Two-step: invalidate the TK2 layout for this attachment's
    /// range, then prod the viewport controller. We fall back to a
    /// text-storage `edited(.editedAttributes, ...)` ping for TK1.
    private func invalidateAttachmentLayout() {
        guard let tv = enclosingTextView() else { return }

        if let tlm = tv.textLayoutManager,
           let tcm = tlm.textContentManager,
           let location = providerLocation(),
           let end = tcm.location(location, offsetBy: 1),
           let range = NSTextRange(location: location, end: end) {
            tlm.invalidateLayout(for: range)
            tlm.textViewportLayoutController.layoutViewport()
            tv.needsDisplay = true
            return
        }

        // TextKit 1 fallback.
        guard let storage = tv.textStorage else { return }
        let nsRange = locateAttachmentRange(in: storage)
        guard nsRange.location != NSNotFound else { return }
        storage.beginEditing()
        storage.edited(.editedAttributes, range: nsRange, changeInLength: 0)
        storage.endEditing()
        tv.needsDisplay = true
    }

    private func providerLocation() -> NSTextLocation? {
        return provider?.location
    }

    private func locateAttachmentRange(in storage: NSTextStorage) -> NSRange {
        let full = NSRange(location: 0, length: storage.length)
        var found = NSRange(location: NSNotFound, length: 0)
        storage.enumerateAttribute(.attachment, in: full, options: []) { value, range, stop in
            if let value = value as AnyObject?, value === self.attachment {
                found = range
                stop.pointee = true
            }
        }
        return found
    }

    private func enclosingTextView() -> NSTextView? {
        var v: NSView? = self
        while let cur = v {
            if let tv = cur as? NSTextView { return tv }
            v = cur.superview
        }
        return nil
    }
}

// MARK: - Slider

/// Slim pill-shaped width slider drawn from scratch. Mirrors the
/// `.rv-slider` design: blurred white background, gray track with a
/// blue fill up to the thumb, white thumb with a soft shadow, and a
/// monospaced percentage readout on the right.
///
/// See `ResizableFigureAttachment` for the `@unchecked Sendable`
/// rationale.
final class FigureSliderView: NSView, @unchecked Sendable {
    private let minValue: CGFloat
    private let maxValue: CGFloat
    private(set) var value: CGFloat
    /// Width used as the 100% reference for the percentage label.
    /// Matches the prototype's `COL_WIDTH`.
    private let columnReference: CGFloat

    /// Continuous changes during drag, plus a final tick on mouse-up.
    var onValueChanged: ((CGFloat, _ isFinal: Bool) -> Void)?
    var onDragStateChanged: ((Bool) -> Void)?

    private let trackWidth: CGFloat = 120
    private let trackHeight: CGFloat = 14
    private let iconWidth: CGFloat = 14
    private let labelWidth: CGFloat = 38
    private let horizontalPadding: CGFloat = 10
    private let verticalPadding: CGFloat = 5
    private let interItemGap: CGFloat = 8

    private var dragActive = false

    /// Geometry of the interactive part of the track. Centered
    /// vertically in the pill; positioned right after the icon. Pure
    /// derived geometry so `hitTest` works before the first draw pass.
    private var trackRect: NSRect {
        let trackOriginX = horizontalPadding + iconWidth + interItemGap
        let trackY = (bounds.height - trackHeight) / 2
        return NSRect(x: trackOriginX, y: trackY, width: trackWidth, height: trackHeight)
    }

    init(min: CGFloat, max: CGFloat, value: CGFloat, columnReference: CGFloat) {
        self.minValue = min
        self.maxValue = max
        self.value = value
        self.columnReference = columnReference
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        setFrameSize(intrinsicContentSize)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override var isFlipped: Bool { false }

    override var intrinsicContentSize: NSSize {
        let w = horizontalPadding + iconWidth + interItemGap
            + trackWidth + interItemGap + labelWidth + horizontalPadding
        let h = verticalPadding + trackHeight + verticalPadding
        return NSSize(width: w, height: h)
    }

    override func draw(_ dirtyRect: NSRect) {
        let pillRect = bounds
        let pillRadius = pillRect.height / 2

        // Background pill (frosted white). NSVisualEffectView would be
        // more authentic but adds layering cost on every figure; the
        // flat alpha read fine on the document's white surface.
        NSGraphicsContext.saveGraphicsState()
        let pill = NSBezierPath(roundedRect: pillRect, xRadius: pillRadius, yRadius: pillRadius)
        NSColor.white.withAlphaComponent(0.94).setFill()
        pill.fill()
        NSColor.black.withAlphaComponent(0.08).setStroke()
        pill.lineWidth = 0.5
        pill.stroke()
        NSGraphicsContext.restoreGraphicsState()

        // Resize-icon (▣) on the leading edge.
        let iconString = NSAttributedString(
            string: "▣",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor(white: 0.43, alpha: 1)
            ]
        )
        let iconSize = iconString.size()
        iconString.draw(at: NSPoint(
            x: horizontalPadding + (iconWidth - iconSize.width) / 2,
            y: (bounds.height - iconSize.height) / 2
        ))

        // Track. Geometry is shared with `hitTest` via the computed
        // `trackRect` property so a click before the first draw pass
        // still lands on the correct strip.
        let track = trackRect
        let trackOriginX = track.origin.x
        let trackY = track.origin.y

        let trackBarHeight: CGFloat = 3
        let trackBar = NSRect(
            x: trackOriginX,
            y: trackY + (trackHeight - trackBarHeight) / 2,
            width: trackWidth,
            height: trackBarHeight
        )
        NSColor.black.withAlphaComponent(0.10).setFill()
        NSBezierPath(roundedRect: trackBar, xRadius: 1.5, yRadius: 1.5).fill()

        // Filled portion up to the thumb.
        let t = normalizedValue
        let fillRect = NSRect(
            x: trackBar.origin.x,
            y: trackBar.origin.y,
            width: trackBar.width * t,
            height: trackBar.height
        )
        NSColor(red: 10/255, green: 132/255, blue: 1.0, alpha: 1).setFill()
        NSBezierPath(roundedRect: fillRect, xRadius: 1.5, yRadius: 1.5).fill()

        // Thumb.
        let thumbDiameter: CGFloat = 14
        let thumbX = trackBar.origin.x + trackBar.width * t - thumbDiameter / 2
        let thumbY = trackBar.midY - thumbDiameter / 2
        let thumbRect = NSRect(x: thumbX, y: thumbY, width: thumbDiameter, height: thumbDiameter)

        // Soft shadow beneath the thumb.
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 3
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.set()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: thumbRect).fill()
        NSGraphicsContext.restoreGraphicsState()

        // Hairline border around the thumb.
        NSColor.black.withAlphaComponent(0.10).setStroke()
        let thumbStroke = NSBezierPath(ovalIn: thumbRect.insetBy(dx: 0.25, dy: 0.25))
        thumbStroke.lineWidth = 0.5
        thumbStroke.stroke()

        // Percentage readout, monospaced, right-aligned.
        let pct = Int((value / max(columnReference, 1)) * 100)
        let label = NSAttributedString(
            string: "\(pct)%",
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .medium),
                .foregroundColor: NSColor(white: 0.43, alpha: 1)
            ]
        )
        let labelSize = label.size()
        let labelOriginX = trackOriginX + trackWidth + interItemGap + labelWidth - labelSize.width
        label.draw(at: NSPoint(
            x: labelOriginX,
            y: (bounds.height - labelSize.height) / 2
        ))
    }

    private var normalizedValue: CGFloat {
        let span = maxValue - minValue
        guard span > 0 else { return 0 }
        return max(0, min(1, (value - minValue) / span))
    }

    // MARK: Hit testing & dragging

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Don't capture clicks while the slider is faded out — the
        // user shouldn't have to figure out where an invisible widget
        // lives. Once the parent's hover fade-in starts, the alpha
        // crosses this threshold quickly and the track becomes live.
        guard alphaValue > 0.05 else { return nil }
        // Only intercept clicks within the track region; everything else
        // (including the pill background and label) is decorative and
        // shouldn't capture mouse-down so the user can still scroll the
        // text view by clicking the pill background.
        let local = convert(point, from: superview)
        if trackRect.insetBy(dx: -8, dy: -8).contains(local) {
            return self
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard trackRect.insetBy(dx: -8, dy: -8).contains(point) else {
            super.mouseDown(with: event)
            return
        }
        dragActive = true
        onDragStateChanged?(true)
        updateValue(forLocalX: point.x, isFinal: false)

        // Modal drag tracking matches AppKit slider behavior — we keep
        // pulling events until the user releases, which lets the user
        // drag outside the slider's bounds without losing the gesture.
        guard let win = window else {
            dragActive = false
            onDragStateChanged?(false)
            return
        }
        while dragActive {
            guard let next = win.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { break }
            let p = convert(next.locationInWindow, from: nil)
            switch next.type {
            case .leftMouseDragged:
                updateValue(forLocalX: p.x, isFinal: false)
            case .leftMouseUp:
                updateValue(forLocalX: p.x, isFinal: true)
                dragActive = false
                onDragStateChanged?(false)
            default:
                break
            }
        }
    }

    private func updateValue(forLocalX x: CGFloat, isFinal: Bool) {
        let span = maxValue - minValue
        guard span > 0, trackRect.width > 0 else { return }
        let t = max(0, min(1, (x - trackRect.origin.x) / trackRect.width))
        let next = minValue + t * span
        if next != value {
            value = next
            needsDisplay = true
        }
        onValueChanged?(next, isFinal)
        if isFinal { needsDisplay = true }
    }

    /// Used by the host view when re-rendering the attachment so the
    /// slider matches a width that was changed externally (e.g. an
    /// attachment bound clamp from a narrower column).
    func setValueExternally(_ newValue: CGFloat) {
        guard !dragActive, newValue != value else { return }
        value = max(minValue, min(maxValue, newValue))
        needsDisplay = true
    }
}
