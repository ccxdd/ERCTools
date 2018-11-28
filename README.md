# ERCTools
Ethereum Token Tools

## WebSocket
```
// balance
EthereumRPC.eth_getBalance(addr: "0xfdfaf22423423432432wfsdfsfd").responseString { [weak self] (r) in

}

// Receipt
EthereumRPC.eth_getTransactionReceipt(tx: "").responseString { (s) in

}

// gasPrice
EthereumRPC.eth_gasPrice().responseString { (r) in

}
```
## ABIEncoding
```
// sendRawTransaction
let transferByID = ABIFunc.call(name: "transferByID", arguments: [.string("1234"),
                                                                  .uint256(UInt(10))])
print(transferByID.encoding)

transferByID.sendRawTransaction { (r) in

}

// eth_call
let isIdAvailable = ABIFunc.call(name: "isIdAvailable", arguments: [.string("my id")])

print(isIdAvailable.encoding)

isIdAvailable.eth_call { (r) in

}
```
