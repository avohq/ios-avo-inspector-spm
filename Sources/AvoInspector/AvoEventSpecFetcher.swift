import Foundation

public typealias AvoEventSpecFetchCompletion = (AvoEventSpecResponse?) -> Void

@objc public class AvoEventSpecFetcher: NSObject {

    private let baseUrl: String
    private let timeout: TimeInterval
    private let env: String
    private var inFlightCallbacks = [String: [AvoEventSpecFetchCompletion]]()
    private let inFlightLock = NSLock()

    @objc public init(timeout: TimeInterval, env: String) {
        self.baseUrl = "https://api.avo.app"
        self.timeout = timeout
        self.env = env
        super.init()
    }

    @objc public init(timeout: TimeInterval, env: String, baseUrl: String) {
        self.baseUrl = baseUrl
        self.timeout = timeout
        self.env = env
        super.init()
    }

    private func generateRequestKey(_ params: AvoFetchEventSpecParams) -> String {
        return "\(params.streamId):\(params.eventName)"
    }

    @objc public func fetchEventSpec(_ params: AvoFetchEventSpecParams,
                                      completion: @escaping AvoEventSpecFetchCompletion) {
        let requestKey = generateRequestKey(params)

        inFlightLock.lock()
        if var existing = inFlightCallbacks[requestKey] {
            existing.append(completion)
            inFlightCallbacks[requestKey] = existing
            inFlightLock.unlock()
            return
        }
        inFlightCallbacks[requestKey] = [completion]
        inFlightLock.unlock()

        fetchInternal(params, requestKey: requestKey)
    }

    private func fetchInternal(_ params: AvoFetchEventSpecParams, requestKey: String) {
        guard env == "dev" || env == "staging" else {
            deliverResult(requestKey, result: nil)
            return
        }

        DispatchQueue.global(qos: .default).async { [weak self] in
            guard let self = self else { return }
            var result: AvoEventSpecResponse?

            do {
                let url = self.buildUrl(params)

                if AvoInspector.isLogging() {
                    NSLog("[avo] Avo Inspector: Fetching event spec for event: %@ url: %@", params.eventName, url)
                }

                let wireResponse = self.makeRequest(url)

                if wireResponse == nil {
                    if AvoInspector.isLogging() {
                        NSLog("[avo] Avo Inspector: Failed to fetch event spec for: %@", params.eventName)
                    }
                } else if !self.hasExpectedShape(wireResponse!) {
                    if AvoInspector.isLogging() {
                        NSLog("[avo] Avo Inspector: Invalid event spec response for: %@", params.eventName)
                    }
                } else {
                    result = AvoEventSpecResponse(fromWire: wireResponse!)
                    if AvoInspector.isLogging() {
                        NSLog("[avo] Avo Inspector: Successfully fetched event spec for: %@ with %lu events",
                              params.eventName, UInt(result?.events.count ?? 0))
                    }
                }
            }

            self.deliverResult(requestKey, result: result)
        }
    }

    private func deliverResult(_ requestKey: String, result: AvoEventSpecResponse?) {
        inFlightLock.lock()
        let callbacks = inFlightCallbacks.removeValue(forKey: requestKey)
        inFlightLock.unlock()

        guard let callbacks = callbacks else { return }
        for cb in callbacks {
            cb(result)
        }
    }

    private func buildUrl(_ params: AvoFetchEventSpecParams) -> String {
        let path = baseUrl + "/trackingPlan/eventSpec"
        var components = URLComponents(string: path)!
        components.queryItems = [
            URLQueryItem(name: "apiKey", value: params.apiKey),
            URLQueryItem(name: "streamId", value: params.streamId),
            URLQueryItem(name: "eventName", value: params.eventName)
        ]
        return components.url?.absoluteString ?? ""
    }

    private func makeRequest(_ url: String) -> AvoEventSpecResponseWire? {
        dispatchPrecondition(condition: .notOnQueue(.main))

        var wireResponse: AvoEventSpecResponseWire?
        let semaphore = DispatchSemaphore(value: 0)

        guard let requestUrl = URL(string: url) else { return nil }

        var request = URLRequest(url: requestUrl)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Use URLSession with nil delegate queue to prevent deadlock
        let session = URLSession(configuration: .default, delegate: nil, delegateQueue: nil)
        let task = session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }

            if let error = error {
                if AvoInspector.isLogging() {
                    NSLog("[avo] Avo Inspector: Network error occurred: %@", error.localizedDescription)
                }
                return
            }

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                if AvoInspector.isLogging() {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                    NSLog("[avo] Avo Inspector: Request failed with status: %ld", statusCode)
                }
                return
            }

            guard let data = data else { return }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    wireResponse = AvoEventSpecResponseWire(dictionary: json)
                } else if AvoInspector.isLogging() {
                    NSLog("[avo] Avo Inspector: Failed to parse response: not a dictionary")
                }
            } catch {
                if AvoInspector.isLogging() {
                    NSLog("[avo] Avo Inspector: Failed to parse response: %@", error.localizedDescription)
                }
            }
        }
        task.resume()

        let waitResult = semaphore.wait(timeout: .now() + timeout)
        if waitResult == .timedOut {
            task.cancel()
        }

        session.finishTasksAndInvalidate()

        return wireResponse
    }

    private func hasExpectedShape(_ response: AvoEventSpecResponseWire) -> Bool {
        guard let metadata = response.metadata else { return false }
        return !response.events.isEmpty
            && !metadata.schemaId.isEmpty
            && !metadata.branchId.isEmpty
            && !metadata.latestActionId.isEmpty
    }
}
