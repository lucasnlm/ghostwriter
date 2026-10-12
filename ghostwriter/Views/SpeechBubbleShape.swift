//
//  SpeechBubbleShape.swift
//  ghostwriter
//

import SwiftUI

struct SpeechBubbleShape: Shape {
    var arrowX: CGFloat
    var arrowOnTop: Bool
    var arrowWidth: CGFloat = 16
    var arrowHeight: CGFloat = 8
    var cornerRadius: CGFloat = 14
    
    var animatableData: CGFloat {
        get { arrowX }
        set { arrowX = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let bodyTop = arrowOnTop ? rect.minY + arrowHeight : rect.minY
        let bodyBottom = arrowOnTop ? rect.maxY : rect.maxY - arrowHeight
        let bodyRect = CGRect(x: rect.minX, y: bodyTop, width: rect.width, height: bodyBottom - bodyTop)
        
        let minArrowX = bodyRect.minX + cornerRadius + (arrowWidth / 2)
        let maxArrowX = bodyRect.maxX - cornerRadius - (arrowWidth / 2)
        let clampedArrowX = max(minArrowX, min(maxArrowX, arrowX))
        
        // Start top-left
        path.move(to: CGPoint(x: bodyRect.minX + cornerRadius, y: bodyRect.minY))
        
        // Top edge (draw arrow if arrowOnTop)
        if arrowOnTop {
            path.addLine(to: CGPoint(x: clampedArrowX - (arrowWidth / 2), y: bodyRect.minY))
            path.addLine(to: CGPoint(x: clampedArrowX, y: rect.minY))
            path.addLine(to: CGPoint(x: clampedArrowX + (arrowWidth / 2), y: bodyRect.minY))
        }
        
        path.addLine(to: CGPoint(x: bodyRect.maxX - cornerRadius, y: bodyRect.minY))
        path.addArc(
            center: CGPoint(x: bodyRect.maxX - cornerRadius, y: bodyRect.minY + cornerRadius),
            radius: cornerRadius,
            startAngle: Angle(degrees: -90),
            endAngle: Angle(degrees: 0),
            clockwise: false
        )
        
        // Right edge
        path.addLine(to: CGPoint(x: bodyRect.maxX, y: bodyRect.maxY - cornerRadius))
        path.addArc(
            center: CGPoint(x: bodyRect.maxX - cornerRadius, y: bodyRect.maxY - cornerRadius),
            radius: cornerRadius,
            startAngle: Angle(degrees: 0),
            endAngle: Angle(degrees: 90),
            clockwise: false
        )
        
        // Bottom edge (draw arrow if !arrowOnTop)
        if !arrowOnTop {
            path.addLine(to: CGPoint(x: clampedArrowX + (arrowWidth / 2), y: bodyRect.maxY))
            path.addLine(to: CGPoint(x: clampedArrowX, y: rect.maxY))
            path.addLine(to: CGPoint(x: clampedArrowX - (arrowWidth / 2), y: bodyRect.maxY))
        }
        
        path.addLine(to: CGPoint(x: bodyRect.minX + cornerRadius, y: bodyRect.maxY))
        path.addArc(
            center: CGPoint(x: bodyRect.minX + cornerRadius, y: bodyRect.maxY - cornerRadius),
            radius: cornerRadius,
            startAngle: Angle(degrees: 90),
            endAngle: Angle(degrees: 180),
            clockwise: false
        )
        
        // Left edge
        path.addLine(to: CGPoint(x: bodyRect.minX, y: bodyRect.minY + cornerRadius))
        path.addArc(
            center: CGPoint(x: bodyRect.minX + cornerRadius, y: bodyRect.minY + cornerRadius),
            radius: cornerRadius,
            startAngle: Angle(degrees: 180),
            endAngle: Angle(degrees: 270),
            clockwise: false
        )
        
        path.closeSubpath()
        return path
    }
}
