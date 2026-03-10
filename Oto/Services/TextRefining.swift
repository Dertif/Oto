import Foundation

protocol TextRefining: AnyObject {
    var availabilityLabel: String { get }
    func refine(request: TextRefinementRequest) async -> TextRefinementResult
}
