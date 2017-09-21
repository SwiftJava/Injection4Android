//
//  AndroidInjection.swift
//  swift-android-injection
//
//  Created by John Holdsworth on 15/09/2017.
//  Copyright © 2017 John Holdsworth. All rights reserved.
//

import Foundation
import zlib

private var pointerSize = MemoryLayout<uintptr_t>.size
private let INJECTION_PORT: UInt16 = 31441

func htons(_ port: UInt16) -> UInt16 {
    return (port << 8) + (port >> 8)
}
let ntohs = htons

func sockaddr_cast(_ p: UnsafeMutableRawPointer) -> UnsafeMutablePointer<sockaddr> {
    return p.assumingMemoryBound(to: sockaddr.self)
}

protocol EntryInfo {
    var offset: Int32 { get }
    var kind: Int32 { get }
}

open class AndroidInjection {

    static var injectionNumber = 0

    open class func connectAndRun() {
        connectAndRun(forMainThread: { $0() } )
    }

    open class func connectAndRun(forMainThread: @escaping (@escaping () -> ()) -> ()) {
        if androidInjectionHost == "NNN.NNN.NNN.NNN" {
            NSLog("Injection: AndroidInjectionHost.swift has not been updated, please build again.")
            return
        }

        DispatchQueue.global(qos: .background).async {
            var serverSocket: Int32 = -1
            while true {
                while true {
                    serverSocket = connectTo(ipAddress: androidInjectionHost, INJECTION_APPNAME: "Injection")
                    if serverSocket >= 0 {
                        break
                    }
                    Thread.sleep(forTimeInterval: 10)
                }

                service(serverSocket: serverSocket, forMainThread: forMainThread)
                Thread.sleep(forTimeInterval: 10)
            }
        }
    }

    open class func connectTo(ipAddress: UnsafePointer<Int8>, INJECTION_APPNAME: UnsafePointer<Int8>) -> Int32 {
        var loaderAddr = sockaddr_in()

        loaderAddr.sin_family = sa_family_t(AF_INET)
        inet_aton(ipAddress, &loaderAddr.sin_addr)
        loaderAddr.sin_port = htons(INJECTION_PORT)

        NSLog("%s attempting connection to: %s:%d", INJECTION_APPNAME, ipAddress, INJECTION_PORT)

        var loaderSocket: Int32 = 0, optval: Int32 = 1
        loaderSocket = socket(Int32(loaderAddr.sin_family), SOCK_STREAM, 0)
        if loaderSocket < 0 {
            NSLog("%s: Could not open socket for injection: %s", INJECTION_APPNAME, strerror(errno))
        }
        else if setsockopt(loaderSocket, Int32(IPPROTO_TCP), TCP_NODELAY, &optval, socklen_t(MemoryLayout.size(ofValue: optval))) < 0 {
            NSLog("%s: Could not set TCP_NODELAY: %s", INJECTION_APPNAME, strerror(errno))
        }
        else if connect(loaderSocket, sockaddr_cast(&loaderAddr), socklen_t(MemoryLayout.size(ofValue: loaderAddr))) < 0 {
            NSLog("%s could not connect: %s", INJECTION_APPNAME, strerror(errno))
        }
        else {
            return loaderSocket
        }

        close(loaderSocket)
        return -1
    }

    open class func service(serverSocket: Int32, forMainThread: @escaping (@escaping () -> ()) -> ()) {
        NSLog("Injection: Connected to \(androidInjectionHost)")

        let serverWrite = fdopen(serverSocket, "w")
        var value: Int32 = Int32(INJECTION_PORT)
        let valueLength = MemoryLayout.size(ofValue: value)
        if serverWrite == nil || fwrite(&value, 1, valueLength, serverWrite) != valueLength {
            NSLog("Injection: Could not write magic to %d: %s", serverSocket, strerror(errno))
            return
        }

        if !#file.withCString( {
            filepath in
            value = Int32(strlen(filepath)+1)
            return fwrite(&value, 1, valueLength, serverWrite) == valueLength &&
                fwrite(filepath, 1, Int(value), serverWrite) == value
        } ) {
            NSLog("Injection: Could not write filepath to %d: %s", serverSocket, strerror(errno))
            return
        }
        fflush(serverWrite)

        let serverRead = fdopen(serverSocket, "r")
        var compressedLength: Int32 = 0, uncompressedLength: Int32 = 0

        while fread(&compressedLength, 1, valueLength, serverRead) == valueLength &&
            fread(&uncompressedLength, 1, valueLength, serverRead) == valueLength,
            var compressedBuffer = malloc(Int(compressedLength)),
            var uncompressedBuffer = malloc(Int(uncompressedLength)) {
                defer {
                    free(compressedBuffer)
                    free(uncompressedBuffer)
                }

                if compressedLength == 1 && uncompressedLength == 1 {
                    continue
                }

                if fread(compressedBuffer, 1, Int(compressedLength), serverRead) != compressedLength {
                    NSLog("Injection: Could not read %d compressed bytes: %s",
                          compressedLength, strerror(errno))
                    break
                }

                NSLog("Injection: received %d/%d bytes", compressedLength, uncompressedLength)

                let libraryPath: String
                if uncompressedLength == 1 {
                    libraryPath = String(cString: compressedBuffer.assumingMemoryBound(to: UInt8.self))
                }
                else {
                    var destLen = uLongf(uncompressedLength)
                    if uncompress(uncompressedBuffer.assumingMemoryBound(to: Bytef.self), &destLen,
                                  compressedBuffer.assumingMemoryBound(to: Bytef.self),
                                  uLong(compressedLength)) != Z_OK || destLen != uLongf(uncompressedLength) {
                        NSLog("Injection: uncompression failure")
                        break
                    }

                    AndroidInjection.injectionNumber += 1
                    libraryPath = NSTemporaryDirectory()+"injection\(AndroidInjection.injectionNumber).so"
                    let libraryFILE = fopen(libraryPath, "w")
                    if libraryFILE == nil ||
                        fwrite(uncompressedBuffer, 1, Int(uncompressedLength), libraryFILE) != uncompressedLength {
                        NSLog("Injection: Could not write library file")
                        break
                    }
                    fclose(libraryFILE)
                }

                forMainThread( {
                    NSLog("Injection: injecting \(libraryPath)...")
                    let error = loadAndInject(library: libraryPath)
                    var status = Int32(error == nil ? 0 : strlen(error)+1)
                    if fwrite(&status, 1, valueLength, serverWrite) != valueLength {
                        NSLog("Injection: Could not write status: %s", strerror(errno))
                    }
                    if error != nil && fwrite(error, 1, Int(status), serverWrite) != status {
                        NSLog("Injection: Could not write error string: %s", strerror(errno))
                    }
                    fflush(serverWrite)
                    NSLog("Injection complete.")
                } )
        }

        NSLog("Injection loop exits")
        fclose(serverWrite)
        fclose(serverRead)
    }

    open class func loadAndInject(library: String) -> UnsafePointer<Int8>? {
        guard let libHandle = dlopen(library, Int32(RTLD_LAZY)) else {
            let error = dlerror()
            NSLog("Load of \(library) failed - \(String(cString: error!))")
            return error
        }

        var info = Dl_info()
        guard dladdr(&pointerSize, &info) != 0 else {
            NSLog("Locating app library failed")
            return nil
        }

        guard let mainHandle = dlopen(info.dli_fname, Int32(RTLD_LAZY | RTLD_NOLOAD)) else {
            NSLog("Load of \(String(cString: info.dli_fname)) failed")
            return nil
        }

        var processed = [UnsafeMutablePointer<UInt8>: Bool]()

        struct TypeEntry: EntryInfo {
            let offset: Int32
            let kind: Int32
        }

        process(libHandle: libHandle, mainHandle: mainHandle,
                entrySymbol: ".swift2_type_metadata_start",
                entryType: TypeEntry.self, processed: &processed)

        struct Conformance: EntryInfo {
            let skip1: Int32
            let offset: Int32
            let skip2: Int32
            let kind: Int32
        }

        process(libHandle: libHandle, mainHandle: mainHandle,
                entrySymbol: ".swift2_protocol_conformances_start",
                entryType: Conformance.self, pointerOffset: MemoryLayout<Int32>.size, processed: &processed)

        return nil
    }

    class func process<T: EntryInfo>(libHandle: UnsafeMutableRawPointer, mainHandle: UnsafeMutableRawPointer,
                                     entrySymbol: String, entryType: T.Type, pointerOffset: Int = 0,
                                     processed: inout [UnsafeMutablePointer<UInt8>: Bool] ) {
        guard let conformance = dlsym(libHandle, entrySymbol) else {
            NSLog("Could not locate \(entrySymbol) entries")
            return
        }

        let ptr = conformance.assumingMemoryBound(to: UInt64.self)
        let len = Int(ptr.pointee)

        let entrySize = MemoryLayout<T>.size
        let entries = len / entrySize
        NSLog("\(entrySymbol) entries: \(entries)")

        let table = (ptr+1).withMemoryRebound(to: UInt8.self, capacity: len) { $0 }
        let start = (ptr+1).withMemoryRebound(to: T.self, capacity: entries) { $0 }

        for i in 0 ..< entries {
            if start[i].kind == 15 {
                let metadata = UnsafeMutablePointer(table + Int(start[i].offset) + i * entrySize + pointerOffset)
                if processed[metadata] == true {
                    continue
                }
                metadata.withMemoryRebound(to: ClassMetadataSwift.self, capacity: 1) {
                    swizzleClass(classMetadata: $0, mainHandle: mainHandle)
                }
                processed[metadata] = true
            }
        }
    }

    static var originals = [String: UnsafeMutablePointer<ClassMetadataSwift>]()

    open class func swizzleClass(classMetadata: UnsafeMutablePointer<ClassMetadataSwift>, mainHandle: UnsafeMutableRawPointer) {
        var info = Dl_info()
        guard dladdr(classMetadata, &info) != 0, let classSymbol = info.dli_sname else {
            NSLog("Could not locate class")
            return
        }

        let classKey = String(cString: classSymbol)
        guard let existingClass = originals[classKey] ?? dlsym(mainHandle, classSymbol)?
            .assumingMemoryBound(to: ClassMetadataSwift.self) else {
                NSLog("Could not locate original class for \(String(cString: classSymbol))")
                return
        }
        originals[classKey] = existingClass

        func byteAddr<T>(_ location: UnsafeMutablePointer<T>) -> UnsafeMutablePointer<UInt8> {
            return location.withMemoryRebound(to: UInt8.self, capacity: 1) { $0 }
        }

        let vtableOffset = byteAddr(&existingClass.pointee.IVarDestroyer) - byteAddr(existingClass)
        let vtableLength = Int(existingClass.pointee.ClassSize -
            existingClass.pointee.ClassAddressPoint) - vtableOffset
        NSLog("\(unsafeBitCast(classMetadata, to: AnyClass.self)), vtable length: \(vtableLength)")
        memcpy(byteAddr(existingClass) + vtableOffset, byteAddr(classMetadata) + vtableOffset, vtableLength)
    }
}


