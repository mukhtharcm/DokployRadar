import Foundation

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

    func endpointURL(for path: String) throws -> URL {
        guard let baseURL = instance.normalizedBaseURL else {
            throw DokployAPIError.invalidBaseURL
        }

        let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return baseURL
            .appendingPathComponent("api", isDirectory: true)
            .appendingPathComponent(trimmedPath, isDirectory: false)
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
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(instance.apiToken, forHTTPHeaderField: "x-api-key")
        request.setValue("Bearer \(instance.apiToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DokployAPIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw DokployAPIError.requestFailed(statusCode: httpResponse.statusCode, message: message)
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw DokployAPIError.decodingFailed(error)
        }
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
}

enum DokployAPIError: LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case requestFailed(statusCode: Int, message: String)
    case decodingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "The Dokploy base URL is invalid."
        case .invalidResponse:
            return "The Dokploy instance returned an invalid response."
        case .requestFailed(let statusCode, let message):
            return "Dokploy request failed (\(statusCode)): \(message)"
        case .decodingFailed(let error):
            return "Failed to decode Dokploy response: \(error.localizedDescription)"
        }
    }
}
