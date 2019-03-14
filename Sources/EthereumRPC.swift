//
//  EthereumRPC
//  ERCTools
//
//  Created by 陈晓东 on 2018/08/24.
//  Copyright © 2018 陈晓东. All rights reserved.
//

import Foundation
import SwiftWebSocket
import SwiftyJSON
import SSLE

public final class EthereumRPC {
    private static let shared = EthereumRPC()
    var ws: SwiftWebSocket.WebSocket!
    var waitingMethods: [Int: Response] = [:]
    var changeStatusClosure: ((Bool) -> Void)?
    var generalErrorClosure: ((String) -> Void)?
    var timer: Timer?
    let timeoutInterval: TimeInterval = 20
    
    private init() {}
    
    public static var isConnected: Bool {
        return shared.ws.readyState == .open
    }
    
    public static func connect(network: Network, changeStatus: ((Bool) -> Void)? = nil) {
        let urlStr = "wss://\(network.rawValue).infura.io/ws/v3/4a994857f9b2458995c780d28b45ccef"
        shared.changeStatusClosure = changeStatus
        shared.ws = WebSocket(urlStr)
        // open
        shared.ws.event.open = {
            print("INFURA 🤝")
            changeStatus?(true)
        }
        // close
        shared.ws.event.close = { code, reason, clean in
            print("INFURA 😫", code, reason, clean)
            changeStatus?(false)
            shared.clearAllResponse()
            DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 5) {
                shared.ws.open()
            }
        }
        // error
        shared.ws.event.error = { error in
            print("INFURA 😫", error)
        }
        // message
        shared.ws.event.message = { message in
            shared.timerStop()
            guard let text = message as? String else { print("❌", "Unknown Message", message); return }
            let json = JSON(parseJSON: text)
            if json["result"].stringValue.count > 0 {
                shared.responseResult(model: String.self, text: text)
            } else if json["result"].dictionary != nil {
                shared.responseResult(model: TxReceipt.self, text: text)
            } else {
                print("❌", text)
                let resp = shared.waitingMethods.removeValue(forKey: json["id"].intValue)
                #if os(iOS)
                resp?.ctrl?.isUserInteractionEnabled = true
                #endif
                guard let msg = json["error"]["message"].string else { return }
                shared.generalErrorClosure?(msg)
                print(msg)
            }
        }
    }
    
    public static func generalErrorMessage(_ c: @escaping (String) -> Void) {
        shared.generalErrorClosure = c
    }
    
    public static func eth_call(data: String, to: String? = nil, from: String? = nil) -> Response {
        let p = Request.ParamItem(from: from, to: to, data: data)
        return generate(request: Request(method: "eth_call", params: [.dict(p), .string("latest")], id: 0))
    }
    
    public static func eth_getBalance(addr: String) -> Response {
        return generate(request: Request(method: "eth_getBalance", params: [.string(addr), .string("latest")], id: 0))
    }
    
    public static func eth_getTransactionCount(addr: String) -> Response {
        return generate(request: Request(method: "eth_getTransactionCount", params: [.string(addr), .string("latest")], id: 0))
    }
    
    public static func eth_getTransactionReceipt(tx: String) -> Response {
        return generate(request: Request(method: "eth_getTransactionReceipt", params: [.string(tx)], id: 0))
    }
    
    public static func sendRawTransaction(tx: String) -> Response {
        return generate(request: Request(method: "eth_sendRawTransaction", params: [.string(tx)], id: 0))
    }
    
    public static func eth_gasPrice() -> Response {
        return generate(request: Request(method: "eth_gasPrice", params: [], id: 0))
    }
    
    private static func generate(request: Request) -> Response {
        var req = request
        let id = Int.random(in: 1 ..< 1_000_000)
        req.id = id
        let rpcResp = Response()
        rpcResp.request = req
        return rpcResp
    }
    
    private func responseResult<T>(model: T.Type, text: String) where T: Codable {
        guard let resp = text.data(using: .utf8)?.tModel(JSONRPCResult<T>.self), let result = resp.result else { return }
        let rpcResp = waitingMethods.removeValue(forKey: resp.id)
        #if os(iOS)
        rpcResp?.ctrl?.isUserInteractionEnabled = true
        #endif
        print("✔️", rpcResp?.request.method ?? "", text)
        if let r = result as? String {
            if r != "0x" {
                rpcResp?.stringClosure?(r)
            } else {
                rpcResp?.errorClosure?()
            }
        } else if let r = result as? TxReceipt {
            rpcResp?.stringClosure?(r.status)
        } else {
            rpcResp?.errorClosure?()
        }
    }
    
    private func timerReset() {
        timer?.invalidate()
        if #available(iOS 10.0, OSX 10.12, *) {
            timer = Timer.scheduledTimer(withTimeInterval: timeoutInterval, repeats: false) { [weak self] (t) in
                print("Websocket Timeout Disconnect ❌")
                self?.ws.close()
                self?.clearAllResponse()
            }
        }
    }
    
    private func timerStop() {
        timer?.invalidate()
    }
    
    private func clearAllResponse() {
        #if os(iOS)
        for r in waitingMethods.values {
            r.ctrl?.isUserInteractionEnabled = true
        }
        #endif
        waitingMethods.removeAll()
    }
}

public extension EthereumRPC {
    public enum Network: String {
        case mainnet
        case ropsten
        case rinkeby
        case kovan
        
        public var chainID: Int {
            switch self {
            case .mainnet: return 1
            case .ropsten: return 3
            case .rinkeby: return 4
            case .kovan: return 42
            }
        }
        
        public var gastrackerWebsite: String {
            switch self {
            case .mainnet: return "https://etherscan.io/gastracker"
            case .ropsten: return "https://ropsten.etherscan.io/gastracker"
            case .rinkeby: return "https://rinkeby.etherscan.io/gastracker"
            case .kovan: return "https://kovan.etherscan.io/gastracker"
            }
        }
    }
    
    public enum Exception: Error {
        case requestDataError
        case networkNotConnect
        case unknown
    }
    
    public struct Request: Codable {
        let jsonrpc = "2.0"
        var method = "eth_call"
        var params: [ParamValue] = []
        var id: Int = 0
        
        public struct ParamItem: Codable {
            var from: String?
            var to: String?
            var data: String?
        }
        
        public enum ParamValue: Codable {
            case dict(ParamItem)
            case string(String)
            
            public func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .dict(let d):
                    try container.encode(d)
                    return
                case .string(let s):
                    try container.encode(s)
                    return
                }
            }
            
            public init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let v = try? container.decode(ParamItem.self) {
                    self = .dict(v)
                } else if let v = try? container.decode(String.self) {
                    self = .string(v)
                } else {
                    throw DecodingError.typeMismatch(ParamValue.self, DecodingError.Context(codingPath: container.codingPath, debugDescription: "Not a JSON"))
                }
            }
        }
    }
    
    public class Response {
        var request: Request!
        fileprivate var stringClosure: ((String) -> Void)?
        fileprivate var errorClosure: (() -> Void)?
        #if os(iOS)
        fileprivate var ctrl: UIView?
        #endif
        
        @discardableResult
        public func responseString(_ completion: @escaping (String) -> Void) -> Self {
            stringClosure = completion
            if shared.ws.readyState == .open {
                try! startWrite()
            } else {
                shared.ws.open()
            }
            return self
        }
        
        @discardableResult
        public func error(_ closure: @escaping () -> Void) -> Self {
            errorClosure = closure
            return self
        }
        
        #if os(iOS)
        @discardableResult
        public func ctrl(_ c: UIView?) -> Self {
            ctrl = c
            ctrl?.isUserInteractionEnabled = false
            return self
        }
        #endif
        
        private func startWrite() throws {
            guard let reqData = request.tJSONString()?.data(using: .utf8) else { throw Exception.requestDataError }
            shared.waitingMethods[request.id] = self
            print("🚀", request.method, request.params.tJSONString() ?? "")
            shared.ws.send(data: reqData)
            shared.timerReset()
        }
    }
    
    public struct JSONRPCResult<T>: Codable where T: Codable {
        let jsonrpc: String
        let id: Int
        var result: T?
    }
    
    public struct TxReceipt: Codable {
        var status: String
    }
}

/* Eg
 {
 "jsonrpc": "2.0",
 "method": "eth_call",
 "params": [{
 "from": "0xb60e8dd61c5d32be8058bb8eb970870f07233155",
 "to": "0xd46e8dd67c5d32be8058bb8eb970870f07244567",
 "data": "0xd46e8dd67c5d32be8d46e8dd67c5d32be8058bb8eb970870f072445675058bb8eb970870f072445675"
 }, "latest"],
 "id": 1
 }
 
 {
 "jsonrpc": "2.0",
 "id": 18,
 "result": "0x00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000"
 }
 */
