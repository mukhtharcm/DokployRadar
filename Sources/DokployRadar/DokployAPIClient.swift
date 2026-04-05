import Foundation

struct DokployAPIClient {
    let instance: DokployInstance
    let session: URLSession

    init(instance: DokployInstance, session: URLSession = .shared) {
        self.instance = instance
        self.session = session
    }

    func fetchSnapshot(now: Date = .now) async throws -> InstanceSnapshot {
        async let projects: [DokployProject] = request(path: "/project.all")
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
        for deployment in deployments {
            guard let application = deployment.application else {
                continue
            }

            if latestDeploymentByAppID[application.applicationId] == nil {
                latestDeploymentByAppID[application.applicationId] = deployment
            }
        }

        let flattened = projects.flatMap { project in
            project.environments.flatMap { environment in
                environment.applications.map { application in
                    MonitoredApplication(
                        id: "\(instance.id.uuidString):\(application.applicationId)",
                        instanceID: instance.id,
                        instanceName: instance.name,
                        instanceHost: instance.hostLabel,
                        projectName: project.name,
                        environmentName: environment.name,
                        applicationId: application.applicationId,
                        name: application.name,
                        applicationStatus: application.applicationStatus,
                        latestDeployment: latestDeploymentByAppID[application.applicationId]
                    )
                }
            }
        }

        return DokploySorter.sort(flattened, now: now)
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
