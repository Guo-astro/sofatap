import UIKit

/// Local touch feedback only. This renderer never knows about the remote cursor,
/// controller or transport. The fixed layer pools bound work even during fast input.
final class TouchParticleRenderer: NSObject {
    private struct Spark {
        var active = false
        var born = 0.0
        var life = 0.0
        var origin = CGPoint.zero
        var velocity = CGPoint.zero
        var size = CGSize.zero
        var rotation = CGFloat.zero
        var alpha: Float = 1
    }
    private struct Ripple {
        var active = false
        var born = 0.0
        var life = 0.0
        var point = CGPoint.zero
        var radius: CGFloat = 0
        var travel: CGFloat = 0
        var alpha: Float = 1
    }
    // A display link retains its target. Keep that target separate and weak so
    // removing the UIKit view never leaves a renderer or a display link alive.
    private final class FrameTarget: NSObject {
        weak var renderer: TouchParticleRenderer?
        @objc func step(_ link: CADisplayLink) { renderer?.step(at: link.timestamp) }
    }

    private let surface = CALayer()
    private let glow = CAGradientLayer()
    private let contactRing = CAShapeLayer()
    private let staticPulse = CAShapeLayer()
    private let mint = UIColor(red: 0.64, green: 1, blue: 0.82, alpha: 1)
    private let ice = UIColor(red: 0.74, green: 0.92, blue: 1, alpha: 1)
    private let white = UIColor(red: 0.98, green: 1, blue: 0.94, alpha: 1)
    private let sparkLayers: [CALayer] = (0..<120).map { _ in CALayer() }
    private let rippleLayers: [CAShapeLayer] = (0..<8).map { _ in CAShapeLayer() }
    private var sparks = [Spark](repeating: Spark(), count: 120)
    private var ripples = [Ripple](repeating: Ripple(), count: 8)
    private var nextSpark = 0
    private var nextRipple = 0
    private var randomState: UInt64 = 0x50FA7A9
    private var displayLink: CADisplayLink?
    private let frameTarget = FrameTarget()
    private var hasContact = false
    private var dragging = false
    private var contactPoint = CGPoint.zero
    private var trailPoint = CGPoint.zero
    private var releasedAt: Double?
    private var lastOrbitEmission = 0.0
    private var dragStartedAt = 0.0
    private var reducedMotion = UIAccessibility.isReduceMotionEnabled
    private var pulseClear: DispatchWorkItem?
    private var canvasBounds = CGRect.zero
#if targetEnvironment(simulator)
    private var previewStart: Double?
    private var previewPhase = -1
    private var previewWasStarted = false
#endif

    init(in layer: CALayer) {
        super.init()
        frameTarget.renderer = self
        surface.masksToBounds = true
        layer.addSublayer(surface)

        glow.type = .radial
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)
        glow.colors = [mint.withAlphaComponent(0.30).cgColor,
                       mint.withAlphaComponent(0.075).cgColor,
                       mint.withAlphaComponent(0).cgColor]
        glow.locations = [0, 0.30, 1]
        glow.bounds = CGRect(x: 0, y: 0, width: 144, height: 144)
        glow.opacity = 0
        surface.addSublayer(glow)
        contactRing.fillColor = UIColor.clear.cgColor
        contactRing.strokeColor = mint.withAlphaComponent(0.45).cgColor
        contactRing.lineWidth = 0.7
        contactRing.opacity = 0
        contactRing.path = UIBezierPath(ovalIn: CGRect(x: -13, y: -13, width: 26, height: 26)).cgPath
        surface.addSublayer(contactRing)

        for spark in sparkLayers {
            spark.opacity = 0
            spark.shadowOffset = .zero
            spark.shadowRadius = 4
            spark.shadowOpacity = 0.6
            surface.addSublayer(spark)
        }
        for ripple in rippleLayers {
            ripple.opacity = 0
            ripple.fillColor = UIColor.clear.cgColor
            ripple.lineWidth = 1
            surface.addSublayer(ripple)
        }
        staticPulse.fillColor = mint.withAlphaComponent(0.11).cgColor
        staticPulse.strokeColor = mint.withAlphaComponent(0.8).cgColor
        staticPulse.lineWidth = 1.5
        staticPulse.opacity = 0
        surface.addSublayer(staticPulse)
        NotificationCenter.default.addObserver(self, selector: #selector(motionPreferenceChanged),
                                               name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
    }

    deinit {
        displayLink?.invalidate()
        pulseClear?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    func layout(in bounds: CGRect) {
        guard bounds != canvasBounds else { return }
        canvasBounds = bounds
        withoutAnimations {
            surface.frame = bounds
            // RemoteView clips the complete pad (including its controls) to its
            // chosen shape. Keep only rectangular bounds here so feedback never
            // disappears inside a valid touch region when that shape changes.
        }
    }

    func beginContact(at point: CGPoint) {
        hasContact = true
        releasedAt = nil
        contactPoint = point
        trailPoint = point
        withoutAnimations {
            glow.position = point
            glow.opacity = reducedMotion ? 0.55 : 1
            contactRing.position = point
            contactRing.opacity = reducedMotion ? 0.5 : 0.65
        }
    }

    /// Contact follows the finger even inside the gesture's stationary tolerance;
    /// the brighter trail is emitted only once movement/scroll is recognized.
    func updateContact(at point: CGPoint) {
        contactPoint = point
        guard hasContact else { return }
        withoutAnimations { glow.position = point; contactRing.position = point }
    }

    func moveTrail(to point: CGPoint, scrolling: Bool = false) {
        guard !reducedMotion else { trailPoint = point; return }
        let dx = point.x - trailPoint.x, dy = point.y - trailPoint.y
        let distance = hypot(dx, dy)
        guard distance >= 3 else { return }
        let steps = min(12, max(1, Int(distance / 4)))
        let direction = atan2(dy, dx)
        let time = CACurrentMediaTime()
        withoutAnimations {
            for index in 1...steps {
                let fraction = CGFloat(index) / CGFloat(steps)
                let position = CGPoint(x: trailPoint.x + dx * fraction, y: trailPoint.y + dy * fraction)
                let scatter = (random() - 0.5) * 11
                let origin = CGPoint(x: position.x - sin(direction) * scatter,
                                     y: position.y + cos(direction) * scatter)
                let speed = CGFloat(10 + random() * 30)
                emitSpark(at: origin,
                          velocity: CGPoint(x: -cos(direction) * speed, y: -sin(direction) * speed),
                          size: CGSize(width: scrolling ? 2 : 2 + random() * 2,
                                       height: scrolling ? 2 : 4 + random() * (dragging ? 14 : 8)),
                          rotation: direction + .pi / 2, life: 0.30 + Double(random()) * 0.45,
                          color: index.isMultiple(of: 3) ? white : (dragging ? ice : mint),
                          alpha: scrolling ? 0.45 : 0.85, at: time)
                if index.isMultiple(of: 2) {
                    let angle = random() * .pi * 2
                    emitSpark(at: origin, velocity: CGPoint(x: cos(angle) * 30, y: sin(angle) * 30),
                              size: CGSize(width: 1.5, height: 1.5), rotation: 0,
                              life: 0.55 + Double(random()) * 0.4, color: mint, alpha: 0.6, at: time)
                }
            }
        }
        trailPoint = point
        startFrames()
    }

    func endContact() {
        hasContact = false
        if reducedMotion {
            withoutAnimations { glow.opacity = 0; contactRing.opacity = 0 }
        } else {
            releasedAt = CACurrentMediaTime()
            startFrames()
        }
    }

    func click(at point: CGPoint, double: Bool) {
        if reducedMotion { staticFeedback(at: point, strong: double); return }
        let time = CACurrentMediaTime()
        withoutAnimations {
            burst(at: point, count: double ? 38 : 20, speed: double ? 140 : 92,
                  color: double ? ice : mint, at: time)
            ripple(at: point, radius: 9, travel: double ? 74 : 51,
                   life: double ? 0.64 : 0.52, color: double ? white : mint, at: time)
            if double {
                ripple(at: point, radius: 26, travel: 64, life: 0.85, color: ice, at: time)
            }
        }
        startFrames()
    }

    func setDragging(_ down: Bool, at point: CGPoint) {
        guard dragging != down else { return }
        dragging = down
        contactPoint = point
        if reducedMotion { staticFeedback(at: point, strong: down); return }
        let time = CACurrentMediaTime()
        withoutAnimations {
            burst(at: point, count: down ? 22 : 12, speed: down ? 70 : 45, color: ice, at: time)
            ripple(at: point, radius: down ? 31 : 17, travel: down ? -12 : 31,
                   life: 0.40, color: ice, at: time)
        }
        lastOrbitEmission = time
        if down { dragStartedAt = time }
        startFrames()
    }

    /// Called for cancellation, backgrounding, disable and window removal.
    func clear() {
        displayLink?.invalidate()
        displayLink = nil
        pulseClear?.cancel()
        pulseClear = nil
        hasContact = false
        dragging = false
        releasedAt = nil
#if targetEnvironment(simulator)
        previewStart = nil
#endif
        withoutAnimations {
            glow.opacity = 0
            contactRing.opacity = 0
            staticPulse.opacity = 0
            for index in sparks.indices { sparks[index].active = false; sparkLayers[index].opacity = 0 }
            for index in ripples.indices { ripples[index].active = false; rippleLayers[index].opacity = 0 }
        }
    }

    @objc private func motionPreferenceChanged() {
        let contactWasActive = hasContact
        let dragWasActive = dragging
        let point = contactPoint
        reducedMotion = UIAccessibility.isReduceMotionEnabled
#if targetEnvironment(simulator)
        let wasPreviewing = previewStart != nil
#endif
        clear()
#if targetEnvironment(simulator)
        if wasPreviewing { return }
#endif
        // Clear the old animation immediately, but preserve the actual contact
        // state so an in-flight drag still has appropriate accessible feedback.
        if contactWasActive {
            beginContact(at: point)
            if dragWasActive { setDragging(true, at: point) }
        }
    }

    private func staticFeedback(at point: CGPoint, strong: Bool) {
        pulseClear?.cancel()
        withoutAnimations {
            let radius: CGFloat = strong ? 22 : 15
            staticPulse.position = point
            staticPulse.path = UIBezierPath(ovalIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)).cgPath
            staticPulse.opacity = 1
        }
        let work = DispatchWorkItem { [weak self] in
            self?.withoutAnimations { self?.staticPulse.opacity = 0 }
        }
        pulseClear = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
    }

    private func burst(at point: CGPoint, count: Int, speed: CGFloat, color: UIColor, at time: Double) {
        for index in 0..<count {
            let angle = CGFloat(index) / CGFloat(count) * .pi * 2 + random() * 0.24
            let velocity = speed * (0.3 + random() * 0.7)
            let size = 1.2 + random() * 1.7
            emitSpark(at: point, velocity: CGPoint(x: cos(angle) * velocity, y: sin(angle) * velocity),
                      size: CGSize(width: size, height: index.isMultiple(of: 3) ? size * 3 : size),
                      rotation: angle + .pi / 2, life: 0.38 + Double(random()) * 0.45,
                      color: index.isMultiple(of: 4) ? white : color, alpha: 0.95, at: time)
        }
    }

    private func emitSpark(at point: CGPoint, velocity: CGPoint, size: CGSize, rotation: CGFloat,
                           life: Double, color: UIColor, alpha: Float, at time: Double) {
        let index = nextSpark
        nextSpark = (nextSpark + 1) % sparks.count
        sparks[index] = Spark(active: true, born: time, life: life, origin: point, velocity: velocity,
                              size: size, rotation: rotation, alpha: alpha)
        let layer = sparkLayers[index]
        layer.backgroundColor = color.cgColor
        layer.shadowColor = color.cgColor
        layer.bounds = CGRect(origin: .zero, size: size)
        layer.cornerRadius = min(size.width, size.height) / 2
        layer.position = point
        layer.opacity = alpha
        layer.transform = CATransform3DMakeRotation(rotation, 0, 0, 1)
    }

    private func ripple(at point: CGPoint, radius: CGFloat, travel: CGFloat, life: Double, color: UIColor, at time: Double) {
        let index = nextRipple
        nextRipple = (nextRipple + 1) % ripples.count
        ripples[index] = Ripple(active: true, born: time, life: life, point: point,
                               radius: radius, travel: travel, alpha: 0.8)
        rippleLayers[index].strokeColor = color.cgColor
    }

    private func startFrames() {
        guard !reducedMotion, displayLink == nil else { return }
        let link = CADisplayLink(target: frameTarget, selector: #selector(FrameTarget.step(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        displayLink = link
        link.add(to: .main, forMode: .common)
    }

    private func step(at time: Double) {
#if targetEnvironment(simulator)
        advancePreview(at: time)
#endif
        var needsFrames = dragging
        withoutAnimations {
            if dragging, hasContact, time - lastOrbitEmission >= 1 / 30 {
                lastOrbitEmission = time
                let angle = CGFloat((time - dragStartedAt) * 3.8)
                for phase in [CGFloat.zero, .pi] {
                    let turn = angle + phase
                    let radius: CGFloat = 23
                    emitSpark(at: CGPoint(x: contactPoint.x + cos(turn) * radius,
                                          y: contactPoint.y + sin(turn) * radius),
                              velocity: CGPoint(x: -sin(turn) * 26, y: cos(turn) * 26),
                              size: CGSize(width: 2.3, height: 2.3), rotation: 0,
                              life: 0.42, color: ice, alpha: 0.95, at: time)
                }
            }
            for index in sparks.indices where sparks[index].active {
                let spark = sparks[index]
                let age = max(0, time - spark.born)
                let progress = age / spark.life
                guard progress < 1 else {
                    sparks[index].active = false
                    sparkLayers[index].opacity = 0
                    continue
                }
                needsFrames = true
                // Exponential deceleration makes a fast bright core leave a soft
                // suspended tail; elapsed time keeps the shape stable across FPS.
                let travel = CGFloat((1 - exp(-age * 3.5)) / 3.5)
                let layer = sparkLayers[index]
                layer.position = CGPoint(x: spark.origin.x + spark.velocity.x * travel,
                                         y: spark.origin.y + spark.velocity.y * travel)
                layer.opacity = spark.alpha * Float(pow(1 - progress, 1.7))
                let scale = CGFloat(1 - progress * 0.55)
                layer.transform = CATransform3DScale(CATransform3DMakeRotation(spark.rotation, 0, 0, 1), scale, scale, 1)
            }
            for index in ripples.indices where ripples[index].active {
                let ripple = ripples[index]
                let progress = max(0, (time - ripple.born) / ripple.life)
                guard progress < 1 else {
                    ripples[index].active = false
                    rippleLayers[index].opacity = 0
                    continue
                }
                needsFrames = true
                let eased = CGFloat(1 - pow(1 - progress, 3))
                let radius = max(1, ripple.radius + ripple.travel * eased)
                let layer = rippleLayers[index]
                layer.position = ripple.point
                layer.path = UIBezierPath(ovalIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)).cgPath
                layer.opacity = ripple.alpha * Float(pow(1 - progress, 1.5))
                layer.lineWidth = 1.2 - CGFloat(progress) * 0.7
            }
            if let releasedAt {
                let opacity = Float(max(0, 1 - (time - releasedAt) / 0.24))
                glow.opacity = opacity
                contactRing.opacity = opacity * 0.65
                if opacity == 0 { self.releasedAt = nil } else { needsFrames = true }
            }
        }
#if targetEnvironment(simulator)
        if previewStart != nil { needsFrames = true }
#endif
        if !needsFrames { displayLink?.invalidate(); displayLink = nil }
    }

    private func random() -> CGFloat {
        // A tiny deterministic PRNG makes simulator captures reproducible. This
        // has no relationship to pairing/security randomness.
        randomState = randomState &* 6_364_136_223_846_793_005 &+ 1
        return CGFloat((randomState >> 33) & 0xFFFFFF) / CGFloat(0xFFFFFF)
    }

    private func withoutAnimations(_ updates: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updates()
        CATransaction.commit()
    }

#if targetEnvironment(simulator)
    /// Explicit simulator-only visual QA. No synthetic UITouch, gesture state,
    /// controller callback, pairing request or desktop input is involved.
    func startPreviewIfRequested() {
        guard !previewWasStarted, canvasBounds.width > 0, !reducedMotion,
              ProcessInfo.processInfo.arguments.contains("--demo"),
              ProcessInfo.processInfo.arguments.contains("--preview-effects") else { return }
        previewWasStarted = true
        previewStart = CACurrentMediaTime()
        startFrames()
    }

    private func advancePreview(at time: Double) {
        guard let previewStart else { return }
        let elapsed = time - previewStart
        guard elapsed < 24 else {
            self.previewStart = nil
            setDragging(false, at: contactPoint)
            endContact()
            return
        }
        let cycle = max(0, elapsed.truncatingRemainder(dividingBy: 8))
        let phase: Int
        if cycle < 0.35 { phase = 0 }
        else if cycle < 2.25 { phase = 1 }
        else if cycle < 2.75 { phase = 2 }
        else if cycle < 3.50 { phase = 3 }
        else if cycle < 4.0 { phase = 4 }
        else if cycle < 4.30 { phase = 5 }
        else if cycle < 6.85 { phase = 6 }
        else { phase = 7 }
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: canvasBounds.width * x, y: canvasBounds.height * y)
        }
        if phase != previewPhase {
            previewPhase = phase
            switch phase {
            case 1: beginContact(at: point(0.27, 0.52))
            case 2: endContact(); click(at: point(0.63, 0.45), double: false)
            case 3: click(at: point(0.43, 0.57), double: true)
            case 5: beginContact(at: point(0.30, 0.48))
            case 6: setDragging(true, at: point(0.30, 0.48))
            case 7: setDragging(false, at: contactPoint); endContact()
            default: break
            }
        }
        if phase == 1 {
            let t = CGFloat((cycle - 0.35) / 1.90)
            let p = point(0.27 + t * 0.40, 0.52 - sin(t * .pi * 1.2) * 0.15)
            updateContact(at: p)
            moveTrail(to: p)
        } else if phase == 6 {
            let t = CGFloat((cycle - 4.30) / 2.55)
            let p = point(0.30 + t * 0.36, 0.48 + sin(t * .pi * 1.4) * 0.13)
            updateContact(at: p)
            moveTrail(to: p)
        }
    }
#endif
}
