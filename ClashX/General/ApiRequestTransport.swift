//
//  ApiRequestTransport.swift
//  ClashX
//
//  Refactored to use AsyncHTTPClient for both network and unix-socket requests.
//

import Foundation
import AsyncHTTPClient
import NIOCore
import NIOHTTP1

/// Lightweight parameter encoding options used locally by ApiRequestTransport
public enum ApiParameterEncoding {
    case url
    case json

    public static let `default` = ApiParameterEncoding.url
}

enum ApiRequestTransport {
    static var unixSocketPath: String?
    static let localRequestBaseURL = "http://localhost"
    static var requestTimeout: TimeAmount = .seconds(30)
    private static let maxPendingStreamBytes = 1 * 1024 * 1024
    private static let maxStreamLineBytes = 64 * 1024
    
    // Debug
    static var debugUseHttpApi: Bool = false

    private enum RequestError: LocalizedError {
        case coreNotRunning
        case missingUnixSocketPath
        case invalidURL
        case invalidResponse
        case connectionFailed(Error)
        case statusCode(Int)

        var errorDescription: String? {
            switch self {
            case .coreNotRunning:
                return "Core is not running"
            case .missingUnixSocketPath:
                return "Unix socket path is not configured"
            case .invalidURL:
                return "Invalid request URL"
            case .invalidResponse:
                return "Invalid response"
            case .connectionFailed(let error):
                return error.localizedDescription
            case .statusCode(let code):
                return "HTTP status code \(code)"
            }
        }
    }

    enum RequestBackend {
        case request(HTTPClientRequest)
        case failure(Error)
    }

	struct Handle {
		let backend: RequestBackend
		let shouldValidate: Bool
		let timeout: TimeAmount?

		func validate() -> Handle {
			return Handle(backend: backend, shouldValidate: true, timeout: timeout)
		}

		var response: DataResponse {
			get async {
				await ApiRequestTransport.makeDataResponse(backend: backend, shouldValidate: shouldValidate, timeout: timeout)
			}
		}

		var responseData: Data {
			get async throws {
				let response = await ApiRequestTransport.makeDataResponse(backend: backend, shouldValidate: shouldValidate, timeout: timeout)
				if let error = response.error {
					throw error
				}
				guard let data = response.data else {
					throw RequestError.invalidResponse
				}
				return data
			}
		}

        func responseDecodable<T: Decodable>(_ type: T.Type, decoder: JSONDecoder = ApiRequestTransport.makeJSONDecoder()) async throws -> T {
            let data = try await responseData
            return try decoder.decode(T.self, from: data)
        }

        var stream: AsyncThrowingStream<String, Error> {
            ApiRequestTransport.makeStream(backend: backend, shouldValidate: shouldValidate)
        }
    }

    static func authHeader() -> [String: String] {
        let secret = ConfigManager.shared.overrideSecret ?? ConfigManager.shared.apiSecret
        return (!secret.isEmpty) ? ["Authorization": "Bearer \(secret)"] : [:]
    }

    static func apiDate(from string: String) -> Date? {
        if !string.contains("T") {
            // "MM-dd HH:mm:ss"
            return DateFormatter.simple.date(from: string)
        }
        // ISO-like: count fractional digits after the dot to pick the right format
        if let dotIndex = string.lastIndex(of: ".") {
            let afterDot = string[string.index(after: dotIndex)...]
            let fractionalDigits = afterDot.prefix(while: \.isNumber).count
            if fractionalDigits >= 5 {
                // provider: 9 fractional digits (nanoseconds)
                return DateFormatter.provider.date(from: string)
            }
        }
        // js: 1 fractional digit (tenths of a second)
        return DateFormatter.js.date(from: string) ?? DateFormatter.provider.date(from: string)
    }

    static func makeJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)

            if let date = apiDate(from: rawValue) {
                return date
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date string '\(rawValue)'")
        }
        return decoder
    }

	@discardableResult
	static func req(
		_ url: String,
		method: HTTPMethod = .GET,
		parameters: [String: Any]? = nil,
		encoding: ApiParameterEncoding = .default,
		requiresCoreRunning: Bool = true,
		timeout: TimeAmount? = nil
	) async -> Handle {
		let isCoreRunning = await MainActor.run {
			ConfigManager.shared.kernelState.isOperational
		}

		if requiresCoreRunning && !isCoreRunning {
			return Handle(backend: .failure(RequestError.coreNotRunning), shouldValidate: false, timeout: timeout)
		}

		let isLocal = RemoteControlManager.selectConfig == nil
		let baseURL = isLocal ? localRequestBaseURL : ConfigManager.apiUrl
		let socketPath: String?

		if isLocal {
			guard let path = unixSocketPath, !path.isEmpty else {
				return Handle(backend: .failure(RequestError.missingUnixSocketPath), shouldValidate: false, timeout: timeout)
			}
			
#if DEBUG
			if debugUseHttpApi {
				socketPath = nil
			} else {
				socketPath = path
			}
#else
			socketPath = path
#endif
		} else {
			socketPath = nil
		}

		guard let clientRequest = buildRequest(
			baseURL: baseURL,
			url: url,
			method: method,
			parameters: parameters,
			encoding: encoding,
			socketPath: socketPath
		) else {
			return Handle(backend: .failure(RequestError.invalidURL), shouldValidate: false, timeout: timeout)
		}

		return Handle(backend: .request(clientRequest), shouldValidate: false, timeout: timeout)
	}


    struct DataResponse {
        let httpResponse: HTTPURLResponse?
        let data: Data?
        let error: Error?
    }

	private static func makeDataResponse(
		backend: RequestBackend,
		shouldValidate: Bool,
		timeout: TimeAmount? = nil
	) async -> DataResponse {
		switch backend {
		case .request(let request):
			do {
				let httpResponse = try await performClientRequest(request, shouldValidate: shouldValidate, timeout: timeout)
                let data = try await streamResponseToData(httpResponse)
                let response = makeHTTPURLResponse(from: httpResponse, requestURL: request.url)
                return DataResponse(httpResponse: response, data: data, error: nil)
            } catch {
                return DataResponse(httpResponse: nil, data: nil, error: error)
            }
        case .failure(let error):
            return DataResponse(httpResponse: nil, data: nil, error: error)
        }
    }

    private static func makeStream(
        backend: RequestBackend,
        shouldValidate: Bool
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream<String, Error>(bufferingPolicy: .bufferingNewest(256)) { continuation in
            let innerTask = Task {
                var bufferArray = [UInt8]()

                func finishNormally() {
                    if !bufferArray.isEmpty, bufferArray.count <= maxStreamLineBytes, let rawLine = String(bytes: bufferArray, encoding: .utf8) {
                        continuation.yield(rawLine.trimmingCharacters(in: .newlines))
                    }
                    continuation.finish()
                }

                do {
                    switch backend {
                    case .failure(let error):
                        throw error
                    case .request(let request):
                        let response = try await performClientRequest(request, shouldValidate: shouldValidate, timeout: .hours(24))

                        for try await buffer in response.body {
                            if Task.isCancelled {
                                break
                            }
                            bufferArray.append(contentsOf: buffer.readableBytesView)
                            if bufferArray.count > maxPendingStreamBytes {
                                bufferArray.removeAll(keepingCapacity: true)
                                continue
                            }
                            while let newlineIndex = bufferArray.firstIndex(of: 10 /* \n */) {
                                let lineBytes = bufferArray[0..<newlineIndex]
                                bufferArray.removeSubrange(0...newlineIndex)
                                if lineBytes.count <= maxStreamLineBytes, let rawLine = String(bytes: lineBytes, encoding: .utf8) {
                                    continuation.yield(rawLine.trimmingCharacters(in: .newlines))
                                }
                            }
                        }

                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }

                        finishNormally()
                    }
                } catch {
                    if (error is CancellationError) || ((error as NSError).domain == NSCocoaErrorDomain && (error as NSError).code == NSUserCancelledError) {
                        continuation.finish()
                    } else if Self.shouldIgnoreStreamEOFError(error) {
                        finishNormally()
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }

            continuation.onTermination = {
                switch $0 {
                case .finished:
                    break
                default:
                    innerTask.cancel()
                }
            }
        }
    }

    private static func shouldIgnoreStreamEOFError(_ error: Error) -> Bool {
        guard let parserError = error as? HTTPParserError else { return false }
        switch parserError {
        case .invalidEOFState:
            return true
        default:
            return false
        }
    }


    private static func buildRequest(
        baseURL: String,
        url: String,
        method: HTTPMethod,
        parameters: [String: Any]?,
        encoding: ApiParameterEncoding,
        socketPath: String? = nil
    ) -> HTTPClientRequest? {
        let requestURLString: String

        if let socketPath = socketPath {
            guard let socketURL = URL(httpURLWithSocketPath: socketPath, uri: url) else { return nil }
            requestURLString = socketURL.absoluteString
        } else {
            guard let fullURL = URL(string: ConfigManager.apiUrl + url) else {
                return nil
            }
            requestURLString = fullURL.absoluteString
        }

        var clientRequest = HTTPClientRequest(url: requestURLString)
        clientRequest.method = method
        clientRequest.headers.add(name: "Accept", value: "application/json, text/plain, */*")

        guard let _ = try? applyEncoding(to: &clientRequest, parameters: parameters, encoding: encoding) else { return nil }

        authHeader().forEach { key, value in
            clientRequest.headers.add(name: key, value: value)
        }

        if socketPath != nil {
            clientRequest.headers.add(name: "Host", value: "localhost")
        }

        return clientRequest
    }

    private static func applyEncoding(
        to request: inout HTTPClientRequest,
        parameters: [String: Any]?,
        encoding: ApiParameterEncoding
    ) throws {
        guard let params = parameters, !params.isEmpty else { return }

        switch encoding {
        case .url:
            if ["GET", "HEAD", "DELETE"].contains(request.method.rawValue.uppercased()) {
                guard var components = URLComponents(string: request.url) else { return }
                var items = components.queryItems ?? []
                items.append(contentsOf: params.map { URLQueryItem(name: $0.key, value: String(describing: $0.value)) })
                components.queryItems = items
                if let newURL = components.string {
                    request.url = newURL
                }
            } else {
                let bodyString = params.map { "\(percentEncode($0.key))=\(percentEncode(String(describing: $0.value)))" }.joined(separator: "&")
                request.headers.add(name: "Content-Type", value: "application/x-www-form-urlencoded; charset=utf-8")
                request.body = .bytes([UInt8](bodyString.utf8))
            }
        case .json:
            guard JSONSerialization.isValidJSONObject(params) else { throw RequestError.invalidResponse }
            let data = try JSONSerialization.data(withJSONObject: params, options: [])
            request.headers.add(name: "Content-Type", value: "application/json")
            request.body = .bytes(data)
        }
    }

    private static func percentEncode(_ s: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    // MARK: - AsyncHTTPClient integration
    // AsyncHTTPClient integration

    
    private static func performClientRequest(
        _ clientRequest: HTTPClientRequest,
        shouldValidate: Bool = false,
        timeout: TimeAmount? = nil
    ) async throws -> HTTPClientResponse {
        let response = try await HTTPClient.shared.execute(clientRequest, timeout: timeout ?? requestTimeout)

        if shouldValidate && !(200 ..< 300).contains(response.status.code) {
            throw RequestError.statusCode(Int(response.status.code))
        }

        return response
    }

    private static func streamResponseToData(_ response: HTTPClientResponse) async throws -> Data {
        var result = Data()
        if let contentLength = response.headers.first(name: "Content-Length"), let length = Int(contentLength) {
            result.reserveCapacity(length)
        }

        for try await buffer in response.body {
            result.append(contentsOf: buffer.readableBytesView)
        }

        return result
    }

    private static func makeHTTPURLResponse(from response: HTTPClientResponse, requestURL: String) -> HTTPURLResponse? {
        guard let url = URL(string: requestURL) ?? URL(string: localRequestBaseURL) else { return nil }

        var headerFields: [String: String] = [:]
        for header in response.headers {
            headerFields[header.name] = header.value
        }

        return HTTPURLResponse(url: url, statusCode: Int(response.status.code), httpVersion: nil, headerFields: headerFields)
    }
}
