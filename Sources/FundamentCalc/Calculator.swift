import Foundation
import Combine

struct CalcResults: Identifiable {
    let id = UUID()
    let loads: LoadResult
    let strip: StripResult
    let slab: SlabResult
    let piles: PileResult
}

enum Calculator {
    static func run(_ p: Project) -> CalcResults {
        let loads = LoadCalc.run(p)
        return CalcResults(loads: loads,
                           strip: StripCalc.run(p, loads),
                           slab: SlabCalc.run(p, loads),
                           piles: PileCalc.run(p, loads))
    }
}

final class AppModel: ObservableObject {
    let project: Project
    @Published var results: CalcResults
    @Published var plan: BuildPlan
    private var bag: AnyCancellable?

    init() {
        let p = Project()
        project = p
        let r = Calculator.run(p)
        results = r
        plan = BuildPlan.make(p, r)
        bag = p.objectWillChange
            .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let r = Calculator.run(self.project)
                self.results = r
                self.plan = BuildPlan.make(self.project, r)
            }
    }
}

final class EditorState: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case select = "Выбор", draw = "Перегородка", opening = "Окна и двери"
        var id: String { rawValue }
    }
    @Published var mode: Mode = .select
    @Published var selectedSegment: String?
    @Published var selectedPartition: UUID?
    @Published var selectedOpening: UUID?
    @Published var openingKind: OpeningKind = .window
    @Published var draftA: V2?
    @Published var draftB: V2?
    @Published var drawMaterial: WallMaterial = .frame150
    @Published var drawOnFoundation = false
    @Published var splitDistance = 3.0
}
