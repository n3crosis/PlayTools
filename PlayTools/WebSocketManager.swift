import Foundation
import Network
import UIKit
import os

class WebSocketManager {
    static let shared = WebSocketManager()
    
    private var connection: NWConnection?
    private struct ActiveTouch {
        var tid: Int?
        var lastPoint: CGPoint
    }
    private var activeTouches: [Int: ActiveTouch] = [:] // touchId from message to Toucher state
    private var heartbeatTimer: Timer?
    private let url = URL(string: "ws://localhost:8088")!
    
    private init() {
        startHeartbeatTimer()
    }
    
    func initialize() {
        
    }
    
    func connect() {
        let parameters = NWParameters.tcp
        let webSocketOptions = NWProtocolWebSocket.Options()
        parameters.defaultProtocolStack.applicationProtocols.insert(webSocketOptions, at: 0)
        
        connection = NWConnection(to: .url(self.url), using: parameters)
        
        connection?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                os_log("WebSocket connected")
                self?.receiveMessage()
            case .failed(let error):
                os_log("WebSocket failed: %@", error.localizedDescription)
                self?.cancelAllActiveTouches()
            case .cancelled:
                os_log("WebSocket cancelled")
                self?.cancelAllActiveTouches()
            default:
                break
            }
        }
        
        connection?.start(queue: .main)
    }
    
    private func receiveMessage() {
        connection?.receiveMessage { [weak self] (data, context, isComplete, error) in
            if let data = data, let message = String(data: data, encoding: .utf8) {
                self?.handleMessage(message)
            }
            if error == nil {
                self?.receiveMessage() // Continue receiving
            }
        }
    }
    
    private func handleMessage(_ message: String) {
        guard let data = message.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            return
        }
        
        handleTouch(json)
    }
    
    private func handleTouch(_ touch: [String: Any]) {
        guard let id = touch["id"] as? Int,
              let phaseStr = touch["phase"] as? String,
              let xPercent = touch["x"] as? Double,
              let yPercent = touch["y"] as? Double else {
            return
        }

        let point = CGPoint(x: CGFloat(xPercent) * mainScreenWidth, y: CGFloat(yPercent) * mainScreenHeight)
        let phase: UITouch.Phase

        switch phaseStr {
        case "began":
            phase = .began
        case "moved":
            phase = .moved
        case "ended":
            phase = .ended
        case "cancelled":
            phase = .cancelled
        default:
            return
        }

        PlayInput.touchQueue.async { [weak self] in
            guard let self = self else { return }
            var context = self.activeTouches[id] ?? ActiveTouch(tid: nil, lastPoint: point)
            var tid = context.tid

            // Don't process non-began phases if we don't have a valid tid
            if phase != .began && tid == nil {
                return
            }

            Toucher.touchcam(point: point, phase: phase, tid: &tid, actionName: "WebSocket", keyName: "\(id)")

            context.lastPoint = point
            context.tid = tid

            switch phase {
            case .began, .moved:
                if tid != nil {
                    self.activeTouches[id] = context
                } else {
                    self.activeTouches.removeValue(forKey: id)
                }
            case .ended, .cancelled:
                self.activeTouches.removeValue(forKey: id)
            default:
                break
            }
        }
    }
    
    private func startHeartbeatTimer() {
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.sendHeartbeat()
        }
    }
    
    private func stopHeartbeatTimer() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }
    
    private func sendHeartbeat() {
        guard let connection = connection, connection.state == .ready else {
            connect()
            return
        }
        
        let message = "ping".data(using: .utf8)!
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "heartbeat", metadata: [metadata])
        
        connection.send(content: message, contentContext: context, isComplete: true, completion: .contentProcessed { [weak self] error in
            if let error = error {
                os_log("[WebSocket] Heartbeat send failed: %@", error.localizedDescription)
                self?.connect()
            }
        })
    }
    
    func disconnect() {
        cancelAllActiveTouches()
        stopHeartbeatTimer()
        connection?.cancel()
        connection = nil
    }

    private func cancelAllActiveTouches() {
        PlayInput.touchQueue.async { [weak self] in
            guard let self = self else { return }
            let touches = self.activeTouches
            self.activeTouches.removeAll()
            for (id, context) in touches {
                var tid = context.tid
                if tid == nil {
                    continue
                }
                let point = context.lastPoint
                Toucher.touchcam(point: point, phase: .cancelled, tid: &tid, actionName: "WebSocket", keyName: "\(id)")
            }
        }
    }
}
