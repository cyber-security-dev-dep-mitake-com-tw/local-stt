import CryptoKit
import Foundation

actor ModelInstaller {
    static let modelURL = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin")!
    static let expectedSHA1 = "e050f7970618a659205450ad97eb95a18d69c9ee"

    func install(progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("LocalSTT/Models", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent("ggml-large-v3-turbo-q5_0.bin")
        if FileManager.default.fileExists(atPath: destination.path), try checksum(destination) == Self.expectedSHA1 { progress(1); return destination }

        let (temporary, response) = try await URLSession.shared.download(for: URLRequest(url: Self.modelURL), delegate: ProgressDelegate(progress: progress))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
        guard try checksum(temporary) == Self.expectedSHA1 else { throw CocoaError(.fileReadCorruptFile) }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination); progress(1)
        return destination
    }

    private func checksum(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var hash = Insecure.SHA1()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private final class ProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let callback: @Sendable (Double) -> Void
    init(progress: @escaping @Sendable (Double) -> Void) { callback = progress }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }; callback(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }
}
