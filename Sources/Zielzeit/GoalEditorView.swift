import SwiftUI
import ZielzeitCore

/// Inline goal editing, replacing the old modal `NSAlert`.
///
/// Parsing is delegated to `GoalStore.parseAmount`, which already understands
/// `100k`, `100.000` and `€100 000` — the view never reimplements validation.
struct GoalEditorView: View {

    @Binding var text: String
    let currentGoal: Double?
    let onSave: (Double) -> Void
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool

    private var parsed: Double? { GoalStore.parseAmount(text) }
    private var isValid: Bool { parsed != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                SectionLabel(text: Strings.yourGoal)
                Text(Strings.whatAreYouAimingFor)
                    .font(.system(size: 15, weight: .semibold))
            }

            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    // The symbol sits where the language puts it, as it does in
                    // every amount the app prints — leading in English, trailing
                    // in German.
                    if AppLanguage.current.currencySymbolLeads { currencySymbol }

                    TextField("100000", text: $text)
                        .textFieldStyle(.plain)
                        .font(Theme.numeric(18, weight: .semibold))
                        .focused($isFocused)
                        .onSubmit(save)

                    if !AppLanguage.current.currencySymbolLeads { currencySymbol }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.quinary)
                        .stroke(isValid ? Theme.accent.opacity(0.5) : Color.clear, lineWidth: 1)
                }

                Button(Strings.save, action: save)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(!isValid)

                Button(Strings.cancel, action: onCancel)
                    .buttonStyle(.plain)
                    .font(Theme.caption)
                    .foregroundStyle(.secondary)
            }

            Text(hint)
                .font(Theme.caption)
                .foregroundStyle(isValid || text.isEmpty ? .secondary : Color.red.opacity(0.9))
                .animation(.none, value: text)
        }
        .onAppear {
            if text.isEmpty, let currentGoal {
                text = String(format: "%.0f", currentGoal)
            }
            // A transient popover from an accessory app needs a nudge before a
            // text field will take keyboard focus.
            DispatchQueue.main.async { isFocused = true }
        }
    }

    private var currencySymbol: some View {
        Text("€")
            .font(Theme.numeric(16, weight: .medium))
            .foregroundStyle(.secondary)
    }

    private var hint: String {
        if text.isEmpty { return Strings.goalHintEmpty }
        guard let parsed else { return Strings.goalHintInvalid }
        return Strings.goalHintValid(Format.euro(parsed))
    }

    private func save() {
        guard let parsed else { return }
        onSave(parsed)
    }
}
