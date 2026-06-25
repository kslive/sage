import SwiftUI

/// Минимальный парсер SVG-path (`d`) → `Path`, масштабируемый под прямоугольник.
/// Поддерживает M m L l H h V v C c S s Q q A a Z z — достаточно для иконок макета.
/// ВАЖНО: дуги (A/a) транскрибируем с ПРОБЕЛАМИ между флагами (`a1.5 1.5 0 0 1 1.5 -1.5`),
/// иначе токенайзер склеит `011.5` в одно число.
public enum SVGPath {
    private enum Token {
        case command(Character)
        case number(CGFloat)
    }

    public static func path(_ d: String, viewBox: CGSize) -> Path {
        var path = Path()
        let tokens = tokenize(d)
        var index = 0
        var current = CGPoint.zero
        var subStart = CGPoint.zero
        var lastControl: CGPoint?
        var command: Character = " "

        func nextNumber() -> CGFloat? {
            while index < tokens.count {
                if case let .number(value) = tokens[index] { index += 1; return value }
                return nil
            }
            return nil
        }

        func addArc(to end: CGPoint, rx rxIn: CGFloat, ry ryIn: CGFloat, large: Bool, sweep: Bool) {
            let start = current
            var rx = abs(rxIn), ry = abs(ryIn)
            if rx == 0 || ry == 0 { path.addLine(to: end); return }
            let x1p = (start.x - end.x) / 2, y1p = (start.y - end.y) / 2
            let lambda = x1p * x1p / (rx * rx) + y1p * y1p / (ry * ry)
            if lambda > 1 { let s = lambda.squareRoot(); rx *= s; ry *= s }
            let sign: CGFloat = (large != sweep) ? 1 : -1
            let num = max(0, rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p)
            let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
            let co = den == 0 ? 0 : sign * (num / den).squareRoot()
            let cxp = co * rx * y1p / ry, cyp = co * -ry * x1p / rx
            let cx = cxp + (start.x + end.x) / 2, cy = cyp + (start.y + end.y) / 2
            func angle(_ ux: CGFloat, _ uy: CGFloat) -> CGFloat { atan2(uy, ux) }
            let theta1 = angle((x1p - cxp) / rx, (y1p - cyp) / ry)
            var dTheta = angle((-x1p - cxp) / rx, (-y1p - cyp) / ry) - theta1
            if !sweep, dTheta > 0 { dTheta -= 2 * .pi }
            if sweep, dTheta < 0 { dTheta += 2 * .pi }
            let segments = max(1, Int(ceil(abs(dTheta) / (.pi / 2))))
            let delta = dTheta / CGFloat(segments)
            let t = 4.0 / 3.0 * tan(delta / 4)
            var a = theta1
            for _ in 0 ..< segments {
                let cosA = cos(a), sinA = sin(a), cosB = cos(a + delta), sinB = sin(a + delta)
                let p0 = CGPoint(x: cx + rx * cosA, y: cy + ry * sinA)
                let p3 = CGPoint(x: cx + rx * cosB, y: cy + ry * sinB)
                let c1 = CGPoint(x: p0.x - t * rx * sinA, y: p0.y + t * ry * cosA)
                let c2 = CGPoint(x: p3.x + t * rx * sinB, y: p3.y - t * ry * cosB)
                path.addCurve(to: p3, control1: c1, control2: c2)
                a += delta
            }
            current = end
            lastControl = nil
        }

        while index < tokens.count {
            if case let .command(char) = tokens[index] {
                command = char
                index += 1
                if char == "Z" || char == "z" {
                    path.closeSubpath()
                    current = subStart
                    continue
                }
            }
            let relative = command.isLowercase
            switch Character(command.lowercased()) {
            case "m":
                guard let x = nextNumber(), let y = nextNumber() else { index += 1; continue }
                current = relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                path.move(to: current)
                subStart = current
                command = relative ? "l" : "L"
                lastControl = nil
            case "l":
                guard let x = nextNumber(), let y = nextNumber() else { index += 1; continue }
                current = relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                path.addLine(to: current)
                lastControl = nil
            case "h":
                guard let x = nextNumber() else { index += 1; continue }
                current = relative ? CGPoint(x: current.x + x, y: current.y) : CGPoint(x: x, y: current.y)
                path.addLine(to: current)
                lastControl = nil
            case "v":
                guard let y = nextNumber() else { index += 1; continue }
                current = relative ? CGPoint(x: current.x, y: current.y + y) : CGPoint(x: current.x, y: y)
                path.addLine(to: current)
                lastControl = nil
            case "c":
                guard let x1 = nextNumber(), let y1 = nextNumber(),
                      let x2 = nextNumber(), let y2 = nextNumber(),
                      let x = nextNumber(), let y = nextNumber() else { index += 1; continue }
                let c1 = relative ? CGPoint(x: current.x + x1, y: current.y + y1) : CGPoint(x: x1, y: y1)
                let c2 = relative ? CGPoint(x: current.x + x2, y: current.y + y2) : CGPoint(x: x2, y: y2)
                let end = relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                path.addCurve(to: end, control1: c1, control2: c2)
                lastControl = c2
                current = end
            case "s":
                guard let x2 = nextNumber(), let y2 = nextNumber(),
                      let x = nextNumber(), let y = nextNumber() else { index += 1; continue }
                let c2 = relative ? CGPoint(x: current.x + x2, y: current.y + y2) : CGPoint(x: x2, y: y2)
                let end = relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                let c1 = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                path.addCurve(to: end, control1: c1, control2: c2)
                lastControl = c2
                current = end
            case "q":
                guard let x1 = nextNumber(), let y1 = nextNumber(),
                      let x = nextNumber(), let y = nextNumber() else { index += 1; continue }
                let c = relative ? CGPoint(x: current.x + x1, y: current.y + y1) : CGPoint(x: x1, y: y1)
                let end = relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                path.addQuadCurve(to: end, control: c)
                lastControl = c
                current = end
            case "a":
                guard let rx = nextNumber(), let ry = nextNumber(), let _ = nextNumber(),
                      let large = nextNumber(), let sweep = nextNumber(),
                      let x = nextNumber(), let y = nextNumber() else { index += 1; continue }
                let end = relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                addArc(to: end, rx: rx, ry: ry, large: large != 0, sweep: sweep != 0)
            default:
                index += 1
            }
        }
        return path
    }

    private static func tokenize(_ d: String) -> [Token] {
        var tokens: [Token] = []
        let chars = Array(d)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isLetter {
                tokens.append(.command(c))
                i += 1
            } else if c == "," || c == " " || c == "\n" || c == "\t" || c == "\r" {
                i += 1
            } else {
                var num = ""
                if c == "+" || c == "-" { num.append(c); i += 1 }
                var seenDot = false
                while i < chars.count {
                    let ch = chars[i]
                    if ch.isNumber {
                        num.append(ch); i += 1
                    } else if ch == "." {
                        if seenDot { break }
                        seenDot = true; num.append(ch); i += 1
                    } else if ch == "e" || ch == "E" {
                        num.append(ch); i += 1
                        if i < chars.count, chars[i] == "+" || chars[i] == "-" { num.append(chars[i]); i += 1 }
                    } else {
                        break
                    }
                }
                if let value = Double(num) { tokens.append(.number(CGFloat(value))) }
            }
        }
        return tokens
    }
}

/// SwiftUI-форма из SVG-path, масштабируемая под `rect`.
public struct SVGShape: Shape {
    let pathData: String
    let viewBox: CGSize

    public init(_ pathData: String, viewBox: CGSize = CGSize(width: 24, height: 24)) {
        self.pathData = pathData
        self.viewBox = viewBox
    }

    public func path(in rect: CGRect) -> Path {
        let base = SVGPath.path(pathData, viewBox: viewBox)
        let scaleX = rect.width / viewBox.width
        let scaleY = rect.height / viewBox.height
        let transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY))
        return base.applying(transform)
    }
}
