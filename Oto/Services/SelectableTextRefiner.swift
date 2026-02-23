import Foundation

final class SelectableTextRefiner: TextRefining {
    private let appleRefiner: TextRefining
    private let lmStudioRefiner: LMStudioTextRefiner

    var provider: TextRefinementProvider

    init(
        provider: TextRefinementProvider = .appleIntelligence,
        appleRefiner: TextRefining = AppleFoundationTextRefiner(),
        lmStudioRefiner: LMStudioTextRefiner = LMStudioTextRefiner()
    ) {
        self.provider = provider
        self.appleRefiner = appleRefiner
        self.lmStudioRefiner = lmStudioRefiner
    }

    var availabilityLabel: String {
        activeRefiner.availabilityLabel
    }

    func updateLMStudioConfiguration(baseURL: String, model: String) {
        lmStudioRefiner.baseURLString = baseURL
        lmStudioRefiner.modelName = model
    }

    func refine(request: TextRefinementRequest) async -> TextRefinementResult {
        await activeRefiner.refine(request: request)
    }

    private var activeRefiner: TextRefining {
        switch provider {
        case .appleIntelligence:
            return appleRefiner
        case .lmStudio:
            return lmStudioRefiner
        }
    }
}
