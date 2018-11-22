//
//  ABIEncoding.swift
//  ERC Tools
//
//  Created by 陈晓东 on 2018/08/20.
//  Copyright © 2018年 陈晓东. All rights reserved.
//

import Foundation
import SSLE
import CryptoSwift

public enum InputSolidityType {
    case address(String)
    case bytes(Array<UInt8>)
    case bytesFixed(Int, Array<UInt8>)
    /// = uint8 value 0,1
    case bool(Bool)
    case string(String)
    /// = uint256
    case uint(UInt)
    case uint8(UInt8)
    case uint32(UInt32)
    case uint128(UInt)
    case uint256(UInt)
    case uintArray([UInt])
    case uint8Array([UInt])
    case uint32Array([UInt])
    case uint128Array([UInt])
    case uint256Array([UInt])
    case addressArray([String])
    
    public var isDynamic: Bool {
        switch self {
        case .string(_), .bytes(_), .uintArray(_), .uint8Array(_), .uint32Array(_), .uint128Array(_), .uint256Array(_), .addressArray(_):
            return true
        default:
            return false
        }
    }
    
    /// 位置 + 长度 + 数组中每个值
    public var lines: Int {
        switch self {
        case .string(_), .bytes(_), .uintArray(_), .uint8Array(_), .uint32Array(_), .uint128Array(_), .uint256Array(_), .addressArray(_):
            return 2 + dataLines
        default:
            return 1
        }
    }
    
    /// 数据行
    public var dataLines: Int {
        switch self {
        case .string(let s):
            let dataCount = (s.data(using: .utf8)?.count ?? 0)
            return dataCount / 32 + (dataCount % 32 == 0 ? 0 : 1)
        case .bytes(let s):
            return s.count / 32 + (s.count % 32 == 0 ? 0 : 1)
        case .uintArray(let a), .uint8Array(let a), .uint32Array(let a), .uint128Array(let a), .uint256Array(let a):
            return a.count
        case .addressArray(let a):
            return a.count
        default:
            return 1
        }
    }
    
    public var typeLength: Int {
        switch self {
        case .string(let s):
            let dataCount = (s.data(using: .utf8)?.count ?? 0)
            return dataCount
        case .bytes(let s):
            return s.count
        case .uintArray(let a), .uint8Array(let a), .uint32Array(let a), .uint128Array(let a), .uint256Array(let a):
            return a.count
        default:
            return 0
        }
    }
    
    public var typeData: String {
        switch self {
        case .string(let s):
            return s.hexString.fill0(len: 64 * dataLines, left: false)
        case .bytes(let s):
            return s.toHexString().fill0(len: 64 * dataLines, left: false)
        case .bytesFixed(let l, let bytes):
            let b = bytes.range(from: 0, to: min(l - 1 , 31)) ?? []
            return b.toHexString().fill0(len: 64, left: false)
        case .address(let s):
            return s.clearAddressPrefix
        case .bool(let b):
            return (b ? 1 : 0).radix(16, len: 64)
        case .uint8(let i):
            return Int(i).radix(16, len: 64)
        case .uint32(let i):
            return Int(i).radix(16, len: 64)
        case .uint128(let i), .uint256(let i), .uint(let i):
            return Int(i).radix(16, len: 64)
        case .uint8Array(let a), .uint32Array(let a), .uint128Array(let a), .uint256Array(let a), .uintArray(let a):
            var strArr: [String] = []
            for i in a {
                let v = Int(i).radix(16, len: 64)
                strArr.append(v)
            }
            return strArr.joined(separator: "")
        case .addressArray(let a):
            var strArr: [String] = []
            for i in a {
                strArr.append(i.clearAddressPrefix)
            }
            return strArr.joined(separator: "")
        }
    }
    
    public var typeEncoding: SolidityTypeEncoding {
        var type = SolidityTypeEncoding()
        if isDynamic {
            type.length = typeLength.radix(16, len: 64)
        }
        type.data = typeData
        return type
    }
    
    public var desc: String {
        switch self {
        case .string(_):
            return "string"
        case .address(_):
            return "address"
        case .bytes(_):
            return "bytes"
        case .bytesFixed(let l, _):
            return "bytes\(min(32, l))"
        case .bool(_):
            return "bool"
        case .uint8(_):
            return "uint8"
        case .uint32(_):
            return "uint32"
        case .uint128(_):
            return "uint128"
        case .uint(_), .uint256(_):
            return "uint256"
        case .uint8Array(_):
            return "uint8[]"
        case .uint32Array(_):
            return "uint32[]"
        case .uint128Array(_):
            return "uint128[]"
        case .uintArray(_), .uint256Array(_):
            return "uint256[]"
        case .addressArray:
            return "address[]"
        }
    }
}

public enum OutputSolidityType {
    case string
    case bytes
    case bytesFixed(Int)
    case bool
    case int
    case address
    
    public func decoding(total: Data, idx: Int) -> Data {
        let start = idx * 32
        switch self {
        case .bytesFixed(let l):
            return total[start ..< start + l]
        case .bool, .int:
            return total[start ..< start + 32]
        case .string, .bytes:
            guard let s = total[start ..< start + 32].hex().hexToInt,
                let len = total[s ..< s + 32].hex().hexToInt, len > 0
                else { return Data() }
            let s2 = s + 32
            return total[s2 ..< s2 + len]
        case .address:
            return total[start + 12 ..< start + 32]
        }
    }
}

public struct SolidityReturnDecode {
    public var dataArray: [Data] = []
    public var arguments: [OutputSolidityType] = []
    
    public func get<T>(index: Int, type: T.Type) -> T? where T: Decodable {
        guard !dataArray.isEmpty else { return nil }
        let i = min(index, dataArray.count - 1)
        let v = dataArray.at(i)!
        let t = arguments.at(i)!
        var result: Decodable
        switch t {
        case .string:
            result = v.tString
        case .int:
            result = v.hex().hexToInt
        case .bool:
            result = (v.hex().hexToInt == 0 ? false : true)
        case .bytesFixed(_), .bytes:
            result = v.bytes
        case .address:
            result = "0x" + v.hex()
        }
        return result as? T
    }
    
    public func model<T>(type: T.Type) -> T? where T: SolidityModelProtocol {
        return T.converModel(self)
    }
}

public struct ABIFunc {
    
    public static func call(name: String, arguments: [InputSolidityType] = []) -> ABIFunc {
        return ABIFunc(name: name, arguments: arguments)
    }
    
    private init(name: String, arguments: [InputSolidityType] = []) {
        self.name = name
        self.arguments = arguments
    }
    
    public var name: String
    
    public var arguments: [InputSolidityType] = []
    
    public var totalLines: Int {
        let lines = arguments.reduce(0, { $0 + $1.lines })
        return lines
    }
    
    public var funcSign: String {
        var signatureArr = [name, "("]
        for (idx, i) in arguments.enumerated() {
            if idx == 0 {
                signatureArr.append(i.desc)
            } else {
                signatureArr.append("," + i.desc)
            }
        }
        signatureArr.append(")")
        let funcSign = signatureArr.joined(separator: "").sha3(.keccak256).subTo(8)?.prefix("0x") ?? ""
        return funcSign
    }
    
    public var encoding: String {
        let argumentCount = arguments.count
        var prevDataLines = 0
        var encodingDataArr: [String] = [funcSign]
        var dynamicTypeArr: [SolidityTypeEncoding] = []
        /// 保存动态类型的头部及非动态类型的值
        for i in arguments {
            var type = i.typeEncoding
            if i.isDynamic {
                /// 第2行到当前type的数据行
                let head = (argumentCount + prevDataLines) * 32
                type.head = head.radix(16, len: 64)
                encodingDataArr.append(type.head!)
                dynamicTypeArr.append(type)
                prevDataLines += (1 + i.dataLines)
            } else {
                encodingDataArr.append(type.data)
            }
        }
        /// 保存动态类型的长度和值
        for i in dynamicTypeArr {
            encodingDataArr.append(i.length!)
            encodingDataArr.append(i.data)
        }
        return encodingDataArr.joined(separator: "")
    }
    
    public static func decoding(_ r: String, arguments: OutputSolidityType...) -> SolidityReturnDecode {
        let d = Data(hex: r)
        var dataArr: [Data] = []
        guard d.count % 32 == 0, d.count > 0 else { return SolidityReturnDecode() }
        for (idx, i) in arguments.enumerated() {
            dataArr.append(i.decoding(total: d, idx: idx))
        }
        return SolidityReturnDecode(dataArray: dataArr, arguments: arguments)
    }
}

public struct SolidityTypeEncoding {
    var head: String?
    var length: String?
    var data: String = ""
}

public extension String {
    public var clearAddressPrefix: String {
        let result = hasPrefix("0x") ? self[index(startIndex, offsetBy: 2)...].tS.lowercased() : lowercased()
        return result.fill0(len: 64)
    }
}
