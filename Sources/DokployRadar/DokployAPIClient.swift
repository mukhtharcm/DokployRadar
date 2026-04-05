import Foundation

struct DokployConnectionSummary: Equatable {
    let projectCount: Int
    let serviceCount: Int
    let deployingCount: Int
    let failedCount: Int
}

struct DokployAPIClient {
    let instance: DokployInstance
    let session: URLSession

    init(instance: DokployInstance, session: URLSession = .shared) {
        self.instance = instance
        self.session = session
    }

    func fetchSnapshot(now: Date = .now) async throws -> InstanceSnapshot {
        async let projects: [DokployProject] = requestInventory()
        async let deployments: [DokployCentralizedDeployment] = request(path: "/deployment.allCentralized")

        let snapshotEntries = try buildEntries(
            projects: await projects,
            deployments: await deployments,
            now: now
        )

        return InstanceSnapshot(
            instance: instance,
            entries: snapshotEntries,
            refreshedAt: now,
            errorMessage: nil
        )
    }

    func testConnection(now: Date = .now) async throws -> DokployConnectionSummary {
        async let projects: [DokployProject] = requestInventory()
        async let deployments: [DokployCentralizedDeployment] = request(path: "/deployment.allCentralized")

        let projectList = try await projects
        let entries = try buildEntries(
            projects: projectList,
            deployments: await deployments,
            now: now
        )

        return DokployConnectionSummary(
            projectCount: projectList.count,
            serviceCount: entries.count,
            deployingCount: entries.filter(\.isDeploying).count,
            failedCount: entries.filter(\.isFailing).count
        )
    }

    func endpointURL(for path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        guard let baseURL = instance.normalizedBaseURL else {
            throw DokployAPIError.invalidBaseURL
        }

        let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let endpoint = baseURL
            .appendingPathComponent("api", isDirectory: true)
            .appendingPathComponent(trimmedPath, isDirectory: false)

        guard !queryItems.isEmpty else {
            return endpoint
        }

        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw DokployAPIError.invalidBaseURL
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw DokployAPIError.invalidBaseURL
        }
        return url
    }

    private func requestInventory() async throws -> [DokployProject] {
        do {
            return try await request(path: "/project.allForPermissions")
        } catch DokployAPIError.requestFailed(let statusCode, _) where statusCode == 404 {
            return try await request(path: "/project.all")
        } catch DokployAPIError.decodingFailed(_) {
            return try await request(path: "/project.all")
        }
    }

    private func request<Response: Decodable>(path: String) async throws -> Response {
        let endpoint = try endpointURL(for: path)
        return try await request(url: endpoint)
    }

    private func request<Response: Decodable>(path: String, queryItems: [URLQueryItem]) async throws -> Response {
        let endpoint = try endpointURL(for: path, queryItems: queryItems)
        return try await request(url: endpoint)
    }

    private func requestJSONObject(path: String, queryItems: [URLQueryItem] = []) async throws -> [String: Any] {
        let endpoint = try endpointURL(for: path, queryItems: queryItems)
        let data = try await requestData(url: endpoint)
        let payload = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = payload as? [String: Any] else {
            throw DokployAPIError.invalidResponse
        }
        return dictionary
    }

    private func requestJSONArray(path: String, queryItems: [URLQueryItem] = []) async throws -> [Any] {
        let endpoint = try endpointURL(for: path, queryItems: queryItems)
        let data = try await requestData(url: endpoint)
        let payload = try JSONSerialization.jsonObject(with: data)
        guard let array = payload as? [Any] else {
            throw DokployAPIError.invalidResponse
        }
        return array
    }

    private func requestString(path: String, queryItems: [URLQueryItem] = []) async throws -> String {
        let endpoint = try endpointURL(for: path, queryItems: queryItems)
        let data = try await requestData(url: endpoint)
        guard let text = String(data: data, encoding: .utf8) else {
            throw DokployAPIError.invalidResponse
        }
        return text
    }

    private func request<Response: Decodable>(url endpoint: URL) async throws -> Response {
        let data = try await requestData(url: endpoint)
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw DokployAPIError.decodingFailed(error)
        }
    }

    private func requestData(url endpoint: URL) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(instance.apiToken, forHTTPHeaderField: "x-api-key")
        request.setValue("Bearer \(instance.apiToken)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw DokployAPIError.transport(error)
        } catch {
            throw DokployAPIError.transport(URLError(.unknown, userInfo: [NSUnderlyingErrorKey: error]))
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DokployAPIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = Self.errorMessage(from: data, statusCode: httpResponse.statusCode)
            throw DokployAPIError.requestFailed(statusCode: httpResponse.statusCode, message: message)
        }

        return data
    }

    func fetchDeploymentHistory(for entry: MonitoredApplication) async throws -> [DokployDeploymentRecord] {
        switch entry.serviceType {
        case .application:
            return try await request(
                path: "/deployment.all",
                queryItems: [URLQueryItem(name: "applicationId", value: entry.applicationId)]
            )
        case .compose:
            return try await request(
                path: "/deployment.allByCompose",
                queryItems: [URLQueryItem(name: "composeId", value: entry.applicationId)]
            )
        case .mariadb, .mongo, .mysql, .postgres, .redis, .libsql:
            return []
        }
    }

    func fetchInspectorDetail(for entry: MonitoredApplication) async throws -> DokployServiceInspectorData {
        switch entry.serviceType {
        case .application:
            let payload = try await requestJSONObject(
                path: "/application.one",
                queryItems: [URLQueryItem(name: "applicationId", value: entry.applicationId)]
            )
            return DokployServiceInspectorParser.applicationDetails(from: payload)

        case .compose:
            async let payloadTask = requestJSONObject(
                path: "/compose.one",
                queryItems: [URLQueryItem(name: "composeId", value: entry.applicationId)]
            )
            async let serviceNamesTask = requestJSONArray(
                path: "/compose.loadServices",
                queryItems: [URLQueryItem(name: "composeId", value: entry.applicationId)]
            )
            async let renderedComposeTask = requestString(
                path: "/compose.getConvertedCompose",
                queryItems: [URLQueryItem(name: "composeId", value: entry.applicationId)]
            )

            let payload = try await payloadTask
            let serviceNames = try await serviceNamesTask.compactMap { $0 as? String }
            let renderedCompose = try await renderedComposeTask

            let mountGroups = try await fetchComposeMountGroups(
                composeID: entry.applicationId,
                serviceNames: serviceNames
            )

            return DokployServiceInspectorParser.composeDetails(
                from: payload,
                serviceNames: serviceNames,
                mountGroups: mountGroups,
                renderedCompose: renderedCompose
            )

        case .mariadb, .mongo, .mysql, .postgres, .redis, .libsql:
            return DokployServiceInspectorData(
                sourceType: nil,
                configurationType: nil,
                repository: nil,
                branch: nil,
                autoDeployEnabled: nil,
                previewDeploymentsEnabled: nil,
                previewDeploymentCount: nil,
                deploymentCount: nil,
                environmentVariableCount: 0,
                mountCount: 0,
                watchPathCount: 0,
                domainLabels: [],
                portLabels: [],
                mountSummaries: [],
                watchPaths: [],
                composeServiceNames: [],
                composeMountGroups: [],
                renderedCompose: nil
            )
        }
    }

    private func fetchComposeMountGroups(
        composeID: String,
        serviceNames: [String]
    ) async throws -> [DokployComposeServiceMountGroup] {
        try await withThrowingTaskGroup(of: DokployComposeServiceMountGroup?.self) { group in
            for serviceName in serviceNames {
                group.addTask {
                    let mounts = try await requestJSONArray(
                        path: "/compose.loadMountsByService",
                        queryItems: [
                            URLQueryItem(name: "composeId", value: composeID),
                            URLQueryItem(name: "serviceName", value: serviceName)
                        ]
                    )

                    let summaries: [DokployMountSummary] = mounts.enumerated().compactMap { index, element in
                        guard let mount = element as? [String: Any] else {
                            return nil
                        }

                        let destination = Self.firstNonEmptyString(
                            mount["Destination"],
                            mount["destination"],
                            mount["Target"],
                            mount["target"]
                        ) ?? "Mount \(index + 1)"

                        let source = Self.firstNonEmptyString(
                            mount["Source"],
                            mount["source"],
                            mount["Name"],
                            mount["name"]
                        )
                        let type = Self.firstNonEmptyString(mount["Type"], mount["type"])
                        let mode = Self.firstNonEmptyString(mount["Mode"], mount["mode"])

                        let subtitleParts = [source, type, mode].compactMap { $0 }
                        return DokployMountSummary(
                            id: "\(serviceName)-\(index)",
                            title: destination,
                            subtitle: subtitleParts.isEmpty ? nil : subtitleParts.joined(separator: " • ")
                        )
                    }

                    guard !summaries.isEmpty else {
                        return nil
                    }

                    return DokployComposeServiceMountGroup(
                        id: serviceName,
                        serviceName: serviceName,
                        mounts: summaries
                    )
                }
            }

            var groups: [DokployComposeServiceMountGroup] = []
            for try await groupItem in group {
                if let groupItem {
                    groups.append(groupItem)
                }
            }

            return groups.sorted {
                $0.serviceName.localizedCaseInsensitiveCompare($1.serviceName) == .orderedAscending
            }
        }
    }

    private static func firstNonEmptyString(_ values: Any?...) -> String? {
        for value in values {
            guard let text = value as? String else {
                continue
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    private func buildEntries(
        projects: [DokployProject],
        deployments: [DokployCentralizedDeployment],
        now: Date
    ) -> [MonitoredApplication] {
        var latestDeploymentByAppID: [String: DokployCentralizedDeployment] = [:]
        var latestDeploymentByComposeID: [String: DokployCentralizedDeployment] = [:]
        for deployment in deployments {
            if let application = deployment.application,
               latestDeploymentByAppID[application.applicationId] == nil {
                latestDeploymentByAppID[application.applicationId] = deployment
            }

            if let compose = deployment.compose,
               latestDeploymentByComposeID[compose.composeId] == nil {
                latestDeploymentByComposeID[compose.composeId] = deployment
            }
        }

        let flattened = projects.flatMap { project -> [MonitoredApplication] in
            project.environments.flatMap { environment -> [MonitoredApplication] in
                var entries: [MonitoredApplication] = []

                entries += environment.applications.compactMap { application in
                    makeEntry(
                        serviceID: application.applicationId,
                        name: application.name,
                        appName: application.appName,
                        status: application.applicationStatus,
                        serviceType: .application,
                        project: project,
                        environment: environment,
                        latestDeployment: latestDeploymentByAppID[application.applicationId]
                    )
                }

                entries += environment.compose.compactMap { compose in
                    makeEntry(
                        serviceID: compose.composeId,
                        name: compose.name,
                        appName: compose.appName,
                        status: compose.composeStatus,
                        serviceType: .compose,
                        project: project,
                        environment: environment,
                        latestDeployment: latestDeploymentByComposeID[compose.composeId]
                    )
                }

                entries += environment.mariadb.compactMap {
                    makeEntry(
                        serviceID: $0.mariadbId,
                        name: $0.name,
                        appName: $0.appName,
                        status: $0.applicationStatus,
                        serviceType: .mariadb,
                        project: project,
                        environment: environment
                    )
                }

                entries += environment.mongo.compactMap {
                    makeEntry(
                        serviceID: $0.mongoId,
                        name: $0.name,
                        appName: $0.appName,
                        status: $0.applicationStatus,
                        serviceType: .mongo,
                        project: project,
                        environment: environment
                    )
                }

                entries += environment.mysql.compactMap {
                    makeEntry(
                        serviceID: $0.mysqlId,
                        name: $0.name,
                        appName: $0.appName,
                        status: $0.applicationStatus,
                        serviceType: .mysql,
                        project: project,
                        environment: environment
                    )
                }

                entries += environment.postgres.compactMap {
                    makeEntry(
                        serviceID: $0.postgresId,
                        name: $0.name,
                        appName: $0.appName,
                        status: $0.applicationStatus,
                        serviceType: .postgres,
                        project: project,
                        environment: environment
                    )
                }

                entries += environment.redis.compactMap {
                    makeEntry(
                        serviceID: $0.redisId,
                        name: $0.name,
                        appName: $0.appName,
                        status: $0.applicationStatus,
                        serviceType: .redis,
                        project: project,
                        environment: environment
                    )
                }

                entries += environment.libsql.compactMap {
                    makeEntry(
                        serviceID: $0.libsqlId,
                        name: $0.name,
                        appName: $0.appName,
                        status: $0.applicationStatus,
                        serviceType: .libsql,
                        project: project,
                        environment: environment
                    )
                }

                return entries
            }
        }

        return DokploySorter.sort(flattened, now: now)
    }

    private func makeEntry(
        serviceID: String,
        name: String?,
        appName: String?,
        status: DokployApplicationStatus?,
        serviceType: DokployServiceType,
        project: DokployProject,
        environment: DokployEnvironment,
        latestDeployment: DokployCentralizedDeployment? = nil
    ) -> MonitoredApplication? {
        guard let name, let status else {
            return nil
        }

        return MonitoredApplication(
            id: "\(instance.id.uuidString):\(serviceType.rawValue):\(serviceID)",
            instanceID: instance.id,
            instanceName: instance.name,
            instanceHost: instance.hostLabel,
            projectName: project.name,
            environmentName: environment.name,
            applicationId: serviceID,
            name: name,
            appName: appName,
            applicationStatus: status,
            serviceType: serviceType,
            latestDeployment: latestDeployment
        )
    }

    private static func errorMessage(from data: Data, statusCode: Int) -> String {
        if let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let detail = payload["detail"] as? String, !detail.isEmpty {
                return detail
            }
            if let message = payload["message"] as? String, !message.isEmpty {
                return message
            }
            if let title = payload["title"] as? String, !title.isEmpty {
                return title
            }
            if let errorName = payload["error_name"] as? String, !errorName.isEmpty {
                return errorName
            }
        }

        let fallback = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback?.isEmpty == false
            ? fallback!
            : HTTPURLResponse.localizedString(forStatusCode: statusCode)
    }
}

enum DokployAPIError: LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case transport(URLError)
    case requestFailed(statusCode: Int, message: String)
    case decodingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "The Dokploy base URL is invalid. Use the full Dokploy hostname, for example https://dokploy.example.com."
        case .invalidResponse:
            return "The Dokploy instance returned an invalid HTTP response."
        case .transport(let error):
            return Self.describeTransportError(error)
        case .requestFailed(let statusCode, let message):
            return Self.describeRequestFailure(statusCode: statusCode, message: message)
        case .decodingFailed(let error):
            return "Dokploy returned a response this app does not understand. The Dokploy instance may be on a newer or incompatible version. \(error.localizedDescription)"
        }
    }

    private static func describeTransportError(_ error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet:
            return "No internet connection. Check your network and try again."
        case .cannotFindHost:
            return "Could not resolve the Dokploy host. Check the URL and DNS configuration."
        case .cannotConnectToHost:
            return "Could not connect to the Dokploy host. Check the URL, port, and whether the instance is reachable."
        case .timedOut:
            return "The Dokploy request timed out. The instance may be slow or unreachable."
        case .secureConnectionFailed,
             .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid,
             .clientCertificateRejected,
             .clientCertificateRequired:
            return "TLS failed while connecting to Dokploy. Check the certificate chain and HTTPS configuration."
        default:
            return "Network error while talking to Dokploy: \(error.localizedDescription)"
        }
    }

    private static func describeRequestFailure(statusCode: Int, message: String) -> String {
        let normalizedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = normalizedMessage.lowercased()

        if statusCode == 401 {
            return "Dokploy rejected the API token. Check that the token is correct and still valid."
        }

        if statusCode == 403, lowercased.contains("browser's signature") || lowercased.contains("browser_signature_banned") {
            return "Cloudflare blocked this request before it reached Dokploy. Allow the app through Cloudflare or relax browser-signature restrictions for the API."
        }

        if statusCode == 403 {
            return "Dokploy denied this request. Check the token permissions and any proxy or WAF rules. \(normalizedMessage)"
        }

        if statusCode == 404 {
            return "Could not find the Dokploy API at this URL. Make sure the base URL points at your Dokploy instance."
        }

        if statusCode >= 500 {
            return "Dokploy returned a server error (\(statusCode)). \(normalizedMessage)"
        }

        return "Dokploy request failed (\(statusCode)). \(normalizedMessage)"
    }
}
