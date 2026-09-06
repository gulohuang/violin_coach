import Combine
import Foundation

/// Holds the live `TuningParameters` and persists them.
///
/// Shared rather than per-tab, and deliberately so: values dialled in on the
/// Fine Tune tab are meant to change how the Practice and Scale tabs behave,
/// or tuning them would be an exercise with no effect. `reset()` is the way
/// back, and it restores the shipped defaults exactly.
///
/// Persisted as one JSON blob under a single key. A parameter added later
/// decodes to its default rather than leaving a half-migrated set behind, and
/// a decode failure falls back to defaults rather than refusing to launch.
@MainActor
public final class TuningStore: ObservableObject {
    public static let shared = TuningStore()

    @Published public var parameters: TuningParameters

    private let defaultsKey = "com.gulohuang.violincoach.tuning"
    private let defaults: UserDefaults
    private var saveCancellable: AnyCancellable?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: defaultsKey),
           let stored = try? JSONDecoder().decode(TuningParameters.self, from: data) {
            parameters = stored
        } else {
            parameters = .default
        }

        // Debounced rather than written on every assignment: a slider drag
        // fires this dozens of times a second, and each one would encode the
        // whole set and hand it to UserDefaults for nothing — only where the
        // finger stops matters.
        saveCancellable = $parameters
            .dropFirst()
            .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
            .sink { [weak self] parameters in self?.save(parameters) }
    }

    public var isDefault: Bool { parameters == .default }

    public func reset() {
        parameters = .default
    }

    private func save(_ parameters: TuningParameters) {
        guard let data = try? JSONEncoder().encode(parameters) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}
