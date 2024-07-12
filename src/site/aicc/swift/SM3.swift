class Sm3Impl {
    // 初始IV常量
    private static let IV: [Int32] = [
        Int32(truncating: 0x7380166F),
        Int32(truncating: 0x4914B2B9),
        Int32(truncating: 0x172442D7),
        Int32(truncating: 0xDA8A0600),
        Int32(truncating: 0xA96F30BC),
        Int32(truncating: 0x163138AA),
        Int32(truncating: 0xE38DEE4D),
        Int32(truncating: 0xB0FB0E4E)
    ]

    private var buff512Bit: [Int8]
    private var buffPoint: Int
    private var dataLength: Int
    private var V: [Int32]
    private var hashValue: String = ""
    private var hashBytes: [Int8] = []

    init() {
        self.buff512Bit = [Int8](repeating: 0, count: 64)
        self.buffPoint = 0
        self.dataLength = 0
        self.V = Sm3Impl.IV
    }

    @discardableResult
    func update(_ data: Int8) -> Sm3Impl {
        self.buff512Bit[self.buffPoint] = data
        self.buffPoint += 1
        self.dataLength += 8
        // 够一个块，立即处理
        if self.buffPoint == 64 {
            // 迭代压缩
            self.processFullBuff(block: self.buff512Bit)
            self.buffPoint = 0
        }
        return self
    }
    
   
    private func stringToBytes(_ input: String) -> [Int8] {
        var result: [Int8] = []
        for byte in input.utf8 {
            result.append(limitToSignedByte(i: Int(byte)))
        }
        return result
    }

    @discardableResult
    func updateString(_ text: String) -> Sm3Impl {
        let bytes = stringToBytes(text)
        return self.updateBytes( bytes,  0,  bytes.count)
    }

    @discardableResult
    func updateBytes(_ data: [Int8], _ inOffset: Int, _ length: Int) -> Sm3Impl {
        for i in 0..<length {
            self.buff512Bit[self.buffPoint] = data[inOffset + i]
            self.buffPoint += 1
            self.dataLength += 8
            // 够一个块，立即处理
            if self.buffPoint == 64 {
                // 迭代压缩
                self.processFullBuff(block: self.buff512Bit)
                self.buffPoint = 0
            }
        }
        return self
    }

    func getHashCode() -> String {
        return self.hashValue
    }

    func getHashBytes() -> [Int8] {
        return self.hashBytes
    }

    @discardableResult
    func finish() -> Sm3Impl {
        // 最后一个块处理
        let end = Array(self.buff512Bit[0..<self.buffPoint])
        let blockLen = end.count * 8
        // 1
        let one: Int8 = limitToSignedByte(i: 128)
        // 需填0长度
        let fillZeroLen = (512 - (blockLen + 65) % 512) - 7
        // 总长度Bit
        let allLen = fillZeroLen + blockLen + 65 + 7
        // 总长度Byte
        let allByteLen = allLen / 8
        //
        var buff = [Int8](repeating: 0, count: allByteLen)
        // 填充数据
        for i in 0..<allByteLen {
            if i < end.count {
                // 填充消息
                buff[i] = end[i]
            } else if i == end.count {
                // 填充1
                buff[i] = one
            } else if i > allByteLen - 5 {
                // 最后四字节填充全部数据的总长度
                buff[i] = limitToSignedByte(i:((self.dataLength >> ((allByteLen - i - 1) * 8)) & 0xFF))
            } else {
                // 填充0
                buff[i] = 0
            }
        }
        // 当剩余缓存中内容大于等于448位时，这里会有两个块
        for i in 0..<(allLen / 512) {
            let block = Array(buff[(i * 512 / 8)..<((i + 1) * 512 / 8)])
            // 迭代压缩
            self.processFullBuff(block: block)
        }
        // 记录杂凑值，重置本实例
        self.generatorHashString()
        self.reset()
        return self
    }

    private func limitToSignedByte(i: Int) -> Int8 {
        let b = i & 0xFF
        var c: Int8 = 0
        if b > 128 {
            c = Int8(b % 128)
            c = -1 * (127 - c + 1)
        }else if b == 128{
            c = -128
        } else {
            c = Int8(b)
        }
        return c
    }

    private func generatorHashString() {
        self.hashBytes = [Int8](repeating: 0, count: 32)
        var off = 0
        for element in self.V {
            self.hashBytes[off] = self.limitToSignedByte(i: (Int(shiftedSignedInt(element , 24)) & 0xff))
            off += 1
            self.hashBytes[off] = self.limitToSignedByte(i: (Int(shiftedSignedInt(element , 16)) & 0xff))
            off += 1
            self.hashBytes[off] = self.limitToSignedByte(i: (Int(shiftedSignedInt(element , 8)) & 0xff))
            off += 1
            self.hashBytes[off] = self.limitToSignedByte(i: Int(element & 0xff))
            off += 1
        }
        // 转16进制大写串
        var result = ""
        for element in self.hashBytes {
            result += String(format: "%02X", Int(element) & 0xff)
        }
        self.hashValue = result
    }

    private func reset() {
        self.V = Sm3Impl.IV
        self.buffPoint = 0
        self.dataLength = 0
    }

    private func processFullBuff(block: [Int8]) {
        // 消息扩展至132个字
        var w = [Int32](repeating: 0, count: 68)
        var offset = 0
        // w0 ~ w15
        for j in 0..<16 {
            let h1 = (Int32(block[offset + 0]) & 0xff) << 24
            let h2 = (Int32(block[offset + 1]) & 0xff) << 16
            let h3 = (Int32(block[offset + 2]) & 0xff) << 8
            let h4 = (Int32(block[offset + 3]) & 0xff)
            w[j] = Int32(h1 | h2 | h3 | h4)
            offset += 4
        }
        // w16 ~ w67
        for j in 16..<68 {
            let wj3 = w[j - 3]
            let r15 = Int32(wj3 << 15) | shiftedSignedInt(wj3 , (32 - 15))
            let wj13 = w[j - 13]
            let r7 = Int32(wj13 << 7) | shiftedSignedInt(wj13 , (32 - 7))
            w[j] = self.P1(x: w[j - 16] ^ w[j - 9] ^ r15) ^ r7 ^ w[j - 6]
        }
        // w'0 ~ w'63
        var w2 = [Int32](repeating: 0, count: 64)
        for j in 0..<w2.count {
            w2[j] = w[j] ^ w[j + 4]
        }

        // 压缩函数
        var A = self.V[0]
        var B = self.V[1]
        var C = self.V[2]
        var D = self.V[3]
        var E = self.V[4]
        var F = self.V[5]
        var G = self.V[6]
        var H = self.V[7]
        for j in 0..<64 {
            let A12 = (A << 12) | shiftedSignedInt(A , (32 - 12))
            // 常量 Tj
            let T_j: Int32 = j < 16 ? ((0x79CC4519 << j) | shiftedSignedInt(0x79CC4519 , (32 - j))) : ((0x7A879D8A << (j % 32)) | shiftedSignedInt(0x7A879D8A , (32 - (j % 32))))
            let S_S = A12 &+ E &+ T_j
            let SS1 = Int32(S_S << 7) | shiftedSignedInt(S_S, (32 - 7))
            let SS2 = SS1 ^ A12
            let TT1: Int32 = j < 16 ? ((A ^ B ^ C) &+ D &+ SS2 &+ w2[j]) : (self.FF1(X: A, Y: B, Z: C) &+ D &+ SS2 &+ w2[j])
            let TT2: Int32 = j < 16 ? ((E ^ F ^ G) &+ H &+ SS1 &+ w[j]) : (self.GG1(x: E, y: F, z: G) &+ H &+ SS1 &+ w[j])
            D = C
            C = Int32(B << 9) | shiftedSignedInt(B , (32 - 9))
            B = A
            A = TT1
            H = G
            G = Int32(F << 19) | shiftedSignedInt(F , (32 - 19))
            F = E
            E = self.P0(x: TT2)
        }
        self.V[0] ^= A
        self.V[1] ^= B
        self.V[2] ^= C
        self.V[3] ^= D
        self.V[4] ^= E
        self.V[5] ^= F
        self.V[6] ^= G
        self.V[7] ^= H
    }

    private func FF1(X: Int32, Y: Int32, Z: Int32) -> Int32 {
        return (X & Y) | (X & Z) | (Y & Z)
    }

    private func GG1(x: Int32, y: Int32, z: Int32) -> Int32 {
        return (x & y) | ((~x) & z)
    }

    private func P0(x: Int32) -> Int32 {
        let x9 = Int32(x << 9) | shiftedSignedInt(x , (32 - 9))
        let x17 = Int32(x << 17) | shiftedSignedInt(x , (32 - 17))
        return x ^ x9 ^ x17
    }

    private func P1(x: Int32) -> Int32 {
        let x15 = Int32(x << 15) | shiftedSignedInt(x ,(32 - 15))
        let x23 = Int32(x << 23) | shiftedSignedInt(x ,(32 - 23))
        return x ^ x15 ^ x23
    }
    // 无符号右移 >>>
    private func shiftedSignedInt(_ signedInt:Int32, _ shift:Int)->Int32{
        let unsignedInt: UInt32 = UInt32(bitPattern: signedInt)
        let shiftedUnsignedInt = unsignedInt >> shift
        return Int32(bitPattern: shiftedUnsignedInt)
    }
}
