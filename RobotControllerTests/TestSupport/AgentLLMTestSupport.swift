import Foundation
@testable import RobotController

actor StubAgentLLMTransport: AgentLLMTransport {
    private(set) var request: URLRequest?
    let dataResponse: Data
    let urlResponse: URLResponse

    init(data: Data, response: URLResponse) {
        dataResponse = data
        urlResponse = response
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        self.request = request
        return (dataResponse, urlResponse)
    }

    func lastRequest() -> URLRequest? {
        request
    }
}
