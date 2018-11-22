//
//  EthereumRPC
//  ERCTools
//
//  Created by 陈晓东 on 2018/08/24.
//  Copyright © 2018 陈晓东. All rights reserved.
//

import Foundation
import Starscream
import SwiftyJSON
import SSLE

public final class EthereumRPC: WebSocketDelegate {
    private static let shared = EthereumRPC()
    var rpcSocket: WebSocket!
    var waitingMethods: [Int: Response] = [:]
    var changeStatusClosure: ((Bool) -> Void)?
    
    private init() {}
    
    public static var isConnected: Bool {
        return shared.rpcSocket.isConnected
    }
    
    public static func connect(network: Network, changeStatus: ((Bool) -> Void)? = nil) {
        let urlStr = "wss://\(network.rawValue).infura.io/ws"
        shared.rpcSocket = WebSocket(url: URL(string: urlStr)!)
        shared.rpcSocket.delegate = shared
        shared.changeStatusClosure = changeStatus
        shared.rpcSocket.connect()
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
        rpcResp?.ctrl?.isUserInteractionEnabled = true
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
    
    // MARK: - WebSocketDelegate
    public func websocketDidConnect(socket: WebSocketClient) {
        print("INFURA 🤝")
        changeStatusClosure?(true)
    }
    
    public func websocketDidDisconnect(socket: WebSocketClient, error: Error?) {
        if let err = error {
            print("INFURA 😫", err.localizedDescription)
            changeStatusClosure?(false)
            waitingMethods.removeAll()
            DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 5) {
                socket.connect()
            }
        }
    }
    
    public func websocketDidReceiveMessage(socket: WebSocketClient, text: String) {
        let json = JSON(parseJSON: text)
        if json["result"].stringValue.count > 0 {
            responseResult(model: String.self, text: text)
        } else if json["result"].dictionary != nil {
            responseResult(model: TxReceipt.self, text: text)
        } else {
            print("❌", text)
            let resp = waitingMethods.removeValue(forKey: json["id"].intValue)
            resp?.ctrl?.isUserInteractionEnabled = true
            guard let msg = json["error"]["message"].string else { return }
            print(msg)
        }
    }
    
    public func websocketDidReceiveData(socket: WebSocketClient, data: Data) {}
}

public extension EthereumRPC {
    public enum Network: String {
        case mainnet
        case ropsten
        case rinkeby
        
        public var chainID: Int {
            switch self {
            case .mainnet: return 1
            case .ropsten: return 3
            case .rinkeby: return 4
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
        fileprivate var ctrl: UIView?
        
        @discardableResult
        public func responseString(_ completion: @escaping (String) -> Void) -> Self {
            stringClosure = completion
            if shared.rpcSocket.isConnected {
                try! startWrite()
            } else {
                shared.rpcSocket.connect()
            }
            return self
        }
        
        @discardableResult
        public func error(_ closure: @escaping () -> Void) -> Self {
            errorClosure = closure
            return self
        }
        
        @discardableResult
        public func ctrl(_ c: UIView?) -> Self {
            ctrl = c
            ctrl?.isUserInteractionEnabled = false
            return self
        }
        
        private func startWrite() throws {
            guard let reqData = request.tJSONString()?.data(using: .utf8) else { throw Exception.requestDataError }
            shared.waitingMethods[request.id] = self
            shared.rpcSocket.write(data: reqData)
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
