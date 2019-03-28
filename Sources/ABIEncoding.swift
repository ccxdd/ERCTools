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
    case bool(Bool)
    case string(String)
    case int(Int)
    case uint(UInt)
    case uint8(UInt8)
    case uint32(UInt32)
    case uint128(UInt)
    case uint256(UInt)
    case uintArray([UInt])
    case uint8Array([UInt8])
    case uint32Array([UInt])
    case uint128Array([UInt])
    case uint256Array([UInt])
    case addressArray([String])
    case uintArrayFixed(Int, [UInt8])
    case intArrayFixed(Int, [Int])
    
    public var isDynamic: Bool {
        switch self {
        case .string, .bytes, .uintArray, .uint8Array, .uint32Array, .uint128Array, .uint256Array, .addressArray:
            return true
        default:
            return false
        }
    }
    
    /// 位置 + 长度 + 数组中每个值
    public var lines: Int {
        switch self {
        case .string, .bytes, .uintArray, .uint8Array, .uint32Array, .uint128Array, .uint256Array, .addressArray:
            return 2 + dataLines
        case .uintArrayFixed(let l, _), .intArrayFixed(let l, _):
            return l
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
        case .uintArray(let a), .uint32Array(let a), .uint128Array(let a), .uint256Array(let a):
            return a.count
        case .uint8Array(let a):
            return a.count
        case .addressArray(let a):
            return a.count
        case .uintArrayFixed(let l, _), .intArrayFixed(let l, _):
            return l
        default:
            return 1
        }
    }
    
    /// Dynamic only
    public var typeLength: (value: Int, hex: String) {
        switch self {
        case .string(let s):
            let dataCount = (s.data(using: .utf8)?.count ?? 0)
            return (dataCount, dataCount.radix(16, len: 64))
        case .bytes(let s):
            return (s.count, s.count.radix(16, len: 64))
        case .uintArray(let a), .uint32Array(let a), .uint128Array(let a), .uint256Array(let a):
            return (a.count, a.count.radix(16, len: 64))
        case .uint8Array(let a):
            return (a.count, a.count.radix(16, len: 64))
        default:
            return (0, "")
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
        case .int(let i):
            return i.radix(16, len: 64)
        case .uint8(let i):
            return Int(i).radix(16, len: 64)
        case .uint32(let i):
            return Int(i).radix(16, len: 64)
        case .uint128(let i), .uint256(let i), .uint(let i):
            return Int(i).radix(16, len: 64)
        case .uint32Array(let a), .uint128Array(let a), .uint256Array(let a), .uintArray(let a):
            var strArr: [String] = []
            for i in a {
                let v = Int(i).radix(16, len: 64)
                strArr.append(v)
            }
            return strArr.joined(separator: "")
        case .uint8Array(let a):
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
        case .uintArrayFixed(let l, let arr):
            var strArr: [String] = []
            for i in 0 ..< l {
                let v = Int(arr.at(i) ?? 0).radix(16, len: 64)
                strArr.append(v)
            }
            return strArr.joined(separator: "")
        case .intArrayFixed(let l, let arr):
            var strArr: [String] = []
            for i in 0 ..< l {
                let v = (arr.at(i) ?? 0).radix(16, len: 64)
                strArr.append(v)
            }
            return strArr.joined(separator: "")
        }
    }
    
    public var desc: String {
        switch self {
        case .string:
            return "string"
        case .address:
            return "address"
        case .bytes:
            return "bytes"
        case .bytesFixed(let l, _):
            return "bytes\(min(32, l))"
        case .bool:
            return "bool"
        case .int:
            return "int256"
        case .uint8:
            return "uint8"
        case .uint32:
            return "uint32"
        case .uint128:
            return "uint128"
        case .uint, .uint256:
            return "uint256"
        case .uint8Array:
            return "uint8[]"
        case .uint32Array:
            return "uint32[]"
        case .uint128Array:
            return "uint128[]"
        case .uintArray, .uint256Array:
            return "uint256[]"
        case .addressArray:
            return "address[]"
        case .uintArrayFixed(let l, _):
            return "uint8[\(l)]"
        case .intArrayFixed(let l, _):
            return "int256[\(l)]"
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
            guard let position = total[start ..< start + 32].hex().hexToInt,
                let len = total[position ..< position + 32].hex().hexToInt, len > 0
                else { return Data() }
            let s2 = position + 32
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
        case .bytesFixed, .bytes:
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
        var encodingDataArr: [String] = [funcSign]
        var totalDataLines = 0
        var dynamicEncodingDataArr: [String] = []
        // 静态类型值lines + 动态类型值lines
        for i in arguments {
            totalDataLines += i.dataLines
            if i.isDynamic {
                dynamicEncodingDataArr.append(i.typeLength.hex)
                dynamicEncodingDataArr.append(i.typeData)
            }
        }
        //
        for i in arguments {
            if i.isDynamic {
                // i 的数据行位置
                let position = totalDataLines * 32
                encodingDataArr.append(position.radix(16, len: 64))
                totalDataLines += i.dataLines + 1   // 1: 数据长度
            } else {
                encodingDataArr.append(i.typeData)
            }
        }
        encodingDataArr.append(contentsOf: dynamicEncodingDataArr)
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

public protocol SolidityModelProtocol {
    static func converModel(_ decode: SolidityReturnDecode) -> Self?
}

public extension String {
    public var clearAddressPrefix: String {
        let result = hasPrefix("0x") ? self[index(startIndex, offsetBy: 2)...].tS.lowercased() : lowercased()
        return result.fill0(len: 64)
    }
}

