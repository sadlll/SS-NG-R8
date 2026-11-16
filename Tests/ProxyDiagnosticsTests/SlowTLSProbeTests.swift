import XCTest
@testable import ProxyDiagnostics

final class SlowTLSProbeTests: XCTestCase {
    func testValidProxyWithSlowTLSHandshakeIsNotReportedAsUnusable() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let certificate = directory.appendingPathComponent("certificate.pem")
        let key = directory.appendingPathComponent("key.pem")
        let config = directory.appendingPathComponent("certificate.conf")
        try """
        [req]
        distinguished_name=dn
        x509_extensions=extensions
        prompt=no
        [dn]
        CN=www.gstatic.com
        [extensions]
        subjectAltName=DNS:www.gstatic.com
        basicConstraints=critical,CA:TRUE
        keyUsage=critical,digitalSignature,keyEncipherment,keyCertSign
        extendedKeyUsage=serverAuth
        """.write(to: config, atomically: true, encoding: .utf8)
        let generated = BoundedCommand.run("/usr/bin/openssl", arguments: ["req", "-x509", "-newkey", "rsa:2048", "-nodes",
            "-days", "1", "-config", config.path, "-keyout", key.path, "-out", certificate.path], timeout: 10)
        XCTAssertEqual(generated.status, 0)
        guard generated.status == 0 else { return }
        // A real SOCKS tunnel and TLS server on loopback. No external DNS or Internet requests.
        let fixture = directory.appendingPathComponent("fixture.py")
        try #"""
        import socket, ssl, sys, time
        from pathlib import Path
        folder=Path(sys.argv[1])
        context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(str(folder/'certificate.pem'),str(folder/'key.pem'))
        def read(connection,length):
            data=b''
            while len(data)<length:
                chunk=connection.recv(length-len(data))
                if not chunk: raise EOFError()
                data+=chunk
            return data
        with socket.socket() as listener:
            listener.bind(('127.0.0.1',0)); listener.listen(1)
            (folder/'port').write_text(str(listener.getsockname()[1]))
            connection,_=listener.accept()
            with connection:
                connection.settimeout(20)
                version,count=read(connection,2); assert version==5
                read(connection,count); connection.sendall(b'\x05\x00')
                version,command,reserved,kind=read(connection,4)
                assert version==5 and command==1 and kind==3
                hostname=read(connection,read(connection,1)[0]); port=read(connection,2)
                assert hostname==b'www.gstatic.com' and port==b'\x01\xbb'
                connection.sendall(b'\x05\x00\x00\x01\x7f\x00\x00\x01\x00\x00')
                time.sleep(6)
                with context.wrap_socket(connection,server_side=True) as tls:
                    request=b''
                    while b'\r\n\r\n' not in request: request+=tls.recv(4096)
                    assert request.startswith(b'GET /generate_204 ')
                    tls.sendall(b'HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n')
        """#.write(to: fixture, atomically: true, encoding: .utf8)
        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = [fixture.path, directory.path]
        server.standardOutput = FileHandle.nullDevice
        server.standardError = FileHandle.nullDevice
        try server.run()
        defer { if server.isRunning { server.terminate() }; server.waitUntilExit() }
        let portFile = directory.appendingPathComponent("port")
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: portFile.path) && server.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        let port = try XCTUnwrap(UInt16(String(contentsOf: portFile)))
        let response = BoundedCommand.run("/usr/bin/curl", arguments: ProxyProbe.curlArguments(port: port) +
            ["--cacert", certificate.path], timeout: 27)
        let latency = ProxyProbe.latency(from: response)
        XCTAssertNotNil(latency, "A working proxy with a 6-second TLS handshake must succeed; curl exit \(response.status), \(response.output)")
        if let latency = latency { XCTAssertGreaterThanOrEqual(latency, 6000) }
    }
}
