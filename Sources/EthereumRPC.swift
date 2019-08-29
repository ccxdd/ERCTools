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
import Alamofire

public protocol RPCNode {
    var wssURL: String { get }
    var httpURL: String { get }
}

public final class EthereumRPC {
    private static let shared = EthereumRPC()
    var ws: SwiftWebSocket.WebSocket!
    var waitingMethods: [Int: Response] = [:]
    var changeStatusClosure: ((Bool) -> Void)?
    var generalErrorClosure: ((String) -> Void)?
    var timer: Timer?
    var connectType: ConnectType = .Https
    let timeoutInterval: TimeInterval = 20
    public var rpcNode: RPCNode!
    
    private init() {}
    
    public static var isConnected: Bool {
        return shared.ws.readyState == .open
    }
    
    public static func connectWSS(changeStatus: ((Bool) -> Void)? = nil) {
        shared.connectType = .WebSocket
        shared.changeStatusClosure = changeStatus
        shared.ws = WebSocket(shared.rpcNode.wssURL)
        shared.wsEvents()
    }
    
    public static func reconnectionWSS() {
        guard shared.rpcNode != nil else { return }
        shared.ws = WebSocket(shared.rpcNode.wssURL)
        shared.wsEvents()
    }
    
    public static func setRPC(node: RPCNode) {
        shared.rpcNode = node
    }
    
    func wsEvents() {
        // open
        ws.event.open = { [weak self] in
            print("INFURA 🤝", self!.rpcNode.wssURL)
            self?.changeStatusClosure?(true)
        }
        // close
        ws.event.close = { [weak self] code, reason, clean in
            print("INFURA 😫", code, reason, clean)
            self?.changeStatusClosure?(false)
            self?.clearAllResponse()
            self?.ws.open()
        }
        // error
        ws.event.error = { error in
            print("INFURA 😫", error)
        }
        // message
        ws.event.message = { [weak self] message in
            self?.timerStop()
            guard let text = message as? String else { print("❌", "Unknown Message", message); return }
            self?.responseRawString(text)
        }
    }
    
    public static func generalErrorMessage(_ c: @escaping (String) -> Void) {
        shared.generalErrorClosure = c
    }
    
    public static func changeConnectStatus(_ c: @escaping (Bool) -> Void) {
        shared.changeStatusClosure = c
    }
    
    public static func eth_call(data: String, to: String? = nil, from: String? = nil) -> Response {
        let p = Request.ParamItem(from: from, to: to, data: data)
        return generate(request: Request(method: "eth_call", params: [.dict(p), .latest], id: 0))
    }
    
    public static func eth_getBalance(addr: String) -> Response {
        return generate(request: Request(method: "eth_getBalance", params: [.string(addr), .latest], id: 0))
    }
    
    public static func eth_getTransactionCount(addr: String) -> Response {
        return generate(request: Request(method: "eth_getTransactionCount", params: [.string(addr), .latest], id: 0))
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
    
    public static func eth_chainId() -> Response {
        return generate(request: Request(method: "eth_chainId", params: [], id: 0))
    }
    
    public static func net_version() -> Response {
        return generate(request: Request(method: "net_version", params: [], id: 0))
    }
    
    public static func eth_getBlockByHash(_ blockHash: String, flag: Bool = false) -> Response {
        return generate(request: Request(method: "eth_getBlockByHash", params: [.string(blockHash), .flag(flag)], id: 0))
    }
    
    public static func eth_getBlockByNumber(_ number: String, flag: Bool = false) -> Response {
        return generate(request: Request(method: "eth_getBlockByNumber", params: [.string(number), .flag(flag)], id: 0))
    }
    
    public static func eth_getLogs(addr: String? = nil, from: String? = nil, to: String? = nil,
                                   topics: [[String]]? = nil, blockHash: String? = nil) -> Response {
        var p = Request.ParamItem(fromBlock: from, toBlock: to, address: addr, blockHash: blockHash, topics: topics)
        if p.blockHash != nil {
            p.fromBlock = nil
            p.toBlock = nil
        }
        return generate(request: Request(method: "eth_getLogs", params: [.dict(p)], id: 0))
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
        } else if let r = result as? TransactionReceipt {
            rpcResp?.stringClosure?(r.status)
        } else {
            rpcResp?.errorClosure?()
        }
    }
    
    private func responseRawString(_ str: String) {
        let json = JSON(parseJSON: str)
        if json["result"].stringValue.count > 0 {
            responseResult(model: String.self, text: str)
        } else if json["result"].dictionary != nil {
            responseResult(model: TransactionReceipt.self, text: str)
        } else {
            print("❌", str)
            let resp = waitingMethods.removeValue(forKey: json["id"].intValue)
            #if os(iOS)
            resp?.ctrl?.isUserInteractionEnabled = true
            #endif
            guard let msg = json["error"]["message"].string else { return }
            generalErrorClosure?(msg)
            print(msg)
        }
    }
    
    private func timerReset() {
        timer?.invalidate()
        if #available(iOS 10.0, OSX 10.12, *) {
            timer = Timer.scheduledTimer(withTimeInterval: timeoutInterval, repeats: false) { [weak self] (t) in
                print("Websocket Timeout Disconnect ❌")
                self?.ws.close()
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
    public enum Exception: Error {
        case requestDataError
        case networkNotConnect
        case unknown
    }
    
    public enum ConnectType: Int {
        case WebSocket
        case Https
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
            var fromBlock: String?
            var toBlock: String?
            var address: String?
            var blockHash: String?
            var topics: [[String]]?
            
            init(from: String? = nil, to: String? = nil, data: String? = nil, fromBlock: String? = nil,
                 toBlock: String? = nil, address: String? = nil, blockHash: String? = nil, topics: [[String]]? = nil) {
                self.from = from
                self.to = to
                self.data = data
                self.toBlock = toBlock
                self.fromBlock = fromBlock
                self.address = address
                self.blockHash = blockHash
                self.topics = topics
            }
        }
        
        public enum ParamValue: Codable {
            case dict(ParamItem)
            case string(String)
            case latest
            case earliest
            case pending
            case flag(Bool)
            
            public func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .dict(let d):
                    try container.encode(d)
                    return
                case .string(let s):
                    try container.encode(s)
                    return
                case .flag(let f):
                    try container.encode(f)
                    return
                case .latest:
                    try container.encode("latest")
                    return
                case .earliest:
                    try container.encode("earliest")
                    return
                case .pending:
                    try container.encode("pending")
                    return
                }
            }
            
            public init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let v = try? container.decode(ParamItem.self) {
                    self = .dict(v)
                } else if let v = try? container.decode(Bool.self) {
                    self = .flag(v)
                } else if let v = try? container.decode(String.self) {
                    switch v {
                    case "latest":
                        self = .latest
                    case "earliest":
                        self = .earliest
                    case "pending":
                        self = .pending
                    default:
                        self = .string(v)
                    }
                } else {
                    throw DecodingError.typeMismatch(ParamValue.self, DecodingError.Context(codingPath: container.codingPath, debugDescription: "Not a JSON"))
                }
            }
        }
    }
    
    public class Response {
        var request: Request!
        fileprivate var stringClosure: ((String) -> Void)?
        fileprivate var genericClosure: Any?
        fileprivate var errorClosure: (() -> Void)?
        #if os(iOS)
        fileprivate var ctrl: UIView?
        #endif
        
        @discardableResult
        public func responseString(_ completion: @escaping (String) -> Void) -> Self {
            return responseT(String.self, completion: completion)
        }
        
        @discardableResult
        public func responseT<T>(_ target: T.Type, completion: @escaping (T) -> Void) -> Self where T: Codable {
            genericClosure = completion
            switch shared.connectType {
            case .WebSocket:
                if shared.ws.readyState == .open {
                    try! startWrite()
                } else {
                    shared.ws.open()
                }
            case .Https:
                print("🚀", request.method, request.params.tJSONString() ?? "")
                MWHttpClient.request(shared.rpcNode.httpURL, method: .post, params: request, encoding: JSONEncoding.default)
                    .error({ (err) in
                        #if os(iOS)
                        self.ctrl?.isUserInteractionEnabled = true
                        #endif
                        self.errorClosure?()
                        print("❌", err.errorMsg ?? "")
                    })
                    .responseRaw { (resp) in
                        #if os(iOS)
                        self.ctrl?.isUserInteractionEnabled = true
                        #endif
                        guard let model = resp.tModel(JSONRPCResult<T>.self), let result = model.result else {
                            print("❌", resp)
                            self.errorClosure?()
                            let json = JSON(parseJSON: resp)
                            guard let msg = json["error"]["message"].string else { return }
                            shared.generalErrorClosure?(msg)
                            return
                        }
                        print("✔️", self.request.method ?? "", resp)
                        completion(result)
                }
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
        public let jsonrpc: String
        public let id: Int
        public var result: T?
    }
    
    public struct TransactionReceipt: Codable {
        public let blockHash: String
        public let blockNumber: String
        public let contractAddress: String?
        public let cumulativeGasUsed: String
        public let from: String
        public let gasUsed: String
        public let logs: [EventLog]
        public let logsBloom: String
        public let status: String
        public let to: String
        public let transactionHash: String
        public let transactionIndex: String
    }
    
    public struct EventLog: Codable {
        public let address: String
        public let topics: [String]
        public let blockHash: String
        public let data: String
        public let blockNumber: String
        public let logIndex: String
        public let removed: Bool
        public let transactionHash: String
        public let transactionIndex: String
        
        public var ownerAddress: String {
            return topics[1].replacingOccurrences(of: "0".repetitions(24), with: "")
        }
        
        public var spenderAddress: String {
            return topics[2].replacingOccurrences(of: "0".repetitions(24), with: "")
        }
    }
    
    public struct BlockHashResult: Codable {
        public var difficulty: String
        public var extraData: String
        public var gasLimit: String
        public var gasUsed: String
        public var hash: String
        public var logsBloom: String
        public var miner: String
        public var mixHash: String
        public var nonce: String
        public var number: String
        public var parentHash: String
        public var receiptsRoot: String
        public var sha3Uncles: String
        public var size: String
        public var stateRoot: String
        public var timestamp: String
        public var totalDifficulty: String
        public var transactions: [String]
        public var transactionsRoot: String
        public var uncles: [String]
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
