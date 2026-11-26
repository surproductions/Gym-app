import SwiftUI

struct FormTip {
    let cues: [String]
    let mistakes: [String]
}

/// Short how-to cues for the built-in exercises. Anything else can ask Claude (saved after the first time).
enum FormTips {
    static let builtIn: [String: FormTip] = [
        "bench": FormTip(cues: ["Squeeze your shoulder blades together and keep them pinned.", "Feet flat, slight arch, butt stays on the bench.", "Lower to mid-chest with elbows about 45° from your body.", "Press up and slightly back toward your face."],
                         mistakes: ["Flaring elbows straight out to the sides.", "Bouncing the bar off your chest.", "Lifting your hips off the bench."]),
        "ohp": FormTip(cues: ["Grip just outside shoulders, forearms vertical.", "Squeeze glutes and abs so your back doesn't arch.", "Move your head back, press, then push your head through once the bar passes it.", "Lock out with the bar over your mid-foot."],
                       mistakes: ["Leaning way back to finish the rep.", "Pressing the bar out in front instead of straight up."]),
        "incdb": FormTip(cues: ["Bench at about 30°, not steeper.", "Lower the dumbbells to upper chest with elbows slightly tucked.", "Press up and slightly together without clanking them."],
                         mistakes: ["Bench too steep (turns it into a shoulder press).", "Cutting the bottom of the rep short."]),
        "pushdown": FormTip(cues: ["Pin your elbows to your sides.", "Push down until your arms are straight, squeeze the triceps.", "Control it on the way up; stop at about 90°."],
                            mistakes: ["Elbows drifting forward.", "Leaning over and using body weight."]),
        "hang": FormTip(cues: ["Hang with shoulders pulled down, not shrugged.", "Curl your pelvis up, don't just lift your legs.", "Lower slowly without swinging."],
                        mistakes: ["Swinging for momentum.", "Only lifting the knees without tilting the hips."]),
        "pullup": FormTip(cues: ["Start from a dead hang, then pull your shoulder blades down first.", "Drive elbows down toward your back pockets.", "Chin over the bar, chest toward the bar.", "Lower all the way under control."],
                          mistakes: ["Half reps that stop short at the bottom.", "Kicking or swinging.", "Shrugging shoulders up to your ears."]),
        "row": FormTip(cues: ["Hinge at the hips, flat back, brace your abs.", "Pull to your lower ribs and squeeze shoulder blades.", "Lower until your arms are straight."],
                       mistakes: ["Standing up more each rep.", "Rounding the lower back.", "Jerking the weight with your hips."]),
        "facepull": FormTip(cues: ["Rope at face height, thumbs facing you.", "Pull toward your forehead and spread the rope apart.", "Finish with hands beside your ears, elbows high."],
                            mistakes: ["Going too heavy and leaning back.", "Pulling to your chest instead of your face."]),
        "curl": FormTip(cues: ["Elbows stay at your sides.", "Curl up, squeeze at the top.", "Lower slowly, all the way down."],
                        mistakes: ["Swinging the body.", "Elbows moving forward.", "Stopping halfway down."]),
        "plank": FormTip(cues: ["Elbows under shoulders.", "Squeeze glutes and pull ribs down.", "Straight line from head to heels."],
                         mistakes: ["Hips sagging.", "Butt sticking up in the air.", "Holding your breath."]),
        "squat": FormTip(cues: ["Feet shoulder-width, toes slightly out.", "Brace your abs, then sit down between your heels.", "Knees track over your toes.", "Go at least to thighs parallel, drive up through mid-foot."],
                         mistakes: ["Knees caving in.", "Heels lifting off the floor.", "Chest dropping forward."]),
        "rdl": FormTip(cues: ["Soft knees, push your hips back like closing a car door.", "Bar or dumbbells slide down your thighs.", "Stop when you feel a big hamstring stretch, then squeeze glutes to stand."],
                       mistakes: ["Rounding the back.", "Squatting the weight down instead of hinging.", "Bar drifting away from your legs."]),
        "lunge": FormTip(cues: ["Long step, back knee drops toward the floor.", "Front knee over your foot.", "Push through the front heel to step forward."],
                         mistakes: ["Short steps that push the knee way past the toes.", "Leaning the torso forward."]),
        "abwheel": FormTip(cues: ["Start on knees, round your upper back slightly.", "Roll out only as far as you can keep your lower back flat.", "Pull back with your abs, not your hips."],
                           mistakes: ["Lower back sagging.", "Rolling out too far too soon."]),
        "sideplank": FormTip(cues: ["Elbow under shoulder.", "Hips up, body in a straight line.", "Top hip slightly forward."],
                             mistakes: ["Hips dropping.", "Rolling the chest toward the floor."]),
        "dips": FormTip(cues: ["Shoulders down, chest up.", "Lower until upper arms are about parallel to the floor.", "Lean slightly forward for chest, stay upright for triceps."],
                        mistakes: ["Going too deep and stressing shoulders.", "Shrugging at the bottom."]),
        "chin": FormTip(cues: ["Palms facing you, shoulder-width grip.", "Pull your chest to the bar, elbows close.", "Full hang at the bottom each rep."],
                        mistakes: ["Kipping or swinging.", "Half reps."]),
        "dbohp": FormTip(cues: ["Dumbbells at shoulder height, palms forward or slightly in.", "Brace abs, press straight up.", "Lower to ear level under control."],
                         mistakes: ["Arching the lower back.", "Clanking the dumbbells together at the top."]),
        "dbrow": FormTip(cues: ["Hand and knee on the bench, flat back.", "Pull the dumbbell to your hip.", "Squeeze your back at the top, lower all the way."],
                         mistakes: ["Twisting the torso to lift it.", "Pulling to the chest with the arm."]),
        "lateral": FormTip(cues: ["Slight bend in the elbows.", "Raise out to the sides to shoulder height.", "Lead with the elbows, pinkies slightly up."],
                           mistakes: ["Swinging heavy weight.", "Shrugging the traps."]),
        "carry": FormTip(cues: ["Stand tall, shoulders back.", "Short, quick steps.", "Squeeze the handles hard."],
                         mistakes: ["Leaning to one side.", "Letting the shoulders round forward."]),
        "seatedpress": FormTip(cues: ["Back flat against the bench.", "Start at shoulder height, press straight up.", "Don't lock out hard at the top."],
                               mistakes: ["Arching off the bench.", "Lowering only halfway."]),
        "cablelat": FormTip(cues: ["Cable from the low pulley across your body.", "Raise out to shoulder height.", "Slow on the way down."],
                            mistakes: ["Using your body to swing it.", "Going above shoulder height."]),
        "ezcurl": FormTip(cues: ["Grip the angled part of the bar.", "Elbows at your sides.", "Squeeze at the top, lower slowly."],
                          mistakes: ["Swinging your back.", "Letting elbows drift forward."]),
        "cgpush": FormTip(cues: ["Hands under shoulders, elbows tucked close.", "Body in a straight line.", "Chest to the floor, press up."],
                          mistakes: ["Elbows flaring out.", "Hips sagging."]),
        "inclinecurl": FormTip(cues: ["Bench at about 45°, arms hang straight down.", "Curl without moving your elbows forward.", "Full stretch at the bottom."],
                               mistakes: ["Sitting up off the bench.", "Swinging."]),
        "ohext": FormTip(cues: ["Elbows point up and stay close to your head.", "Lower behind your head for a deep stretch.", "Extend fully."],
                         mistakes: ["Elbows flaring out wide.", "Arching your lower back."]),
        "legraise5": FormTip(cues: ["Hang with shoulders active.", "Raise legs by tilting your pelvis up.", "Lower slowly. For L-sit, keep legs straight and push your shoulders down."],
                             mistakes: ["Swinging.", "Bending the knees for the L-sit when you mean to keep them straight."]),
        "crunch5": FormTip(cues: ["Kneel and hold the rope by your head.", "Crunch your ribs toward your hips.", "Hips stay still; your abs do the work."],
                           mistakes: ["Pulling with the arms.", "Sitting back onto your heels."]),
    ]

    static func cacheKey(_ ex: Exercise) -> String { "formtip-" + ex.name.lowercased() }
}

struct FormTipsSheet: View {
    let exercise: Exercise
    @Environment(\.dismiss) private var dismiss
    @State private var aiText: String?
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if let tip = FormTips.builtIn[exercise.id] {
                    Section("Do this") {
                        ForEach(tip.cues, id: \.self) { Label($0, systemImage: "checkmark.circle").foregroundStyle(.primary) }
                    }
                    Section("Avoid") {
                        ForEach(tip.mistakes, id: \.self) { Label($0, systemImage: "xmark.octagon").foregroundStyle(.primary) }
                    }
                } else if let aiText {
                    Section { MarkdownText(text: aiText) }
                } else {
                    Section {
                        Text("There are no built-in tips for \(exercise.name) yet. Claude can write some (about a cent, saved for next time).")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button {
                            Task { await ask() }
                        } label: {
                            HStack {
                                if loading { ProgressView().padding(.trailing, 6) }
                                Label(loading ? "Writing tips…" : "Get tips from Claude", systemImage: "sparkles")
                            }
                        }
                        .disabled(loading)
                        if let error { Text(error).font(.caption).foregroundStyle(.red) }
                    }
                }
                Section {
                    Text("\(exercise.scheme) · rest \(formatClock(exercise.rest))")
                        .font(.subheadline).foregroundStyle(.secondary)
                } footer: {
                    Text("If something hurts (not just burns), stop and swap the exercise.")
                }
            }
            .navigationTitle(exercise.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { aiText = UserDefaults.standard.string(forKey: FormTips.cacheKey(exercise)) }
        }
    }

    private func ask() async {
        loading = true
        error = nil
        defer { loading = false }
        let prompt = """
        Give quick form tips for the gym exercise "\(exercise.name)".
        Use exactly two markdown headings: "## Do this" (3 to 4 short bullets) and "## Avoid" (2 to 3 short bullets).
        Plain language, under 120 words, no intro.
        """
        do {
            let text = try await NutritionService.askClaude(content: [["type": "text", "text": prompt]], maxTokens: 2000)
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(clean, forKey: FormTips.cacheKey(exercise))
            aiText = clean
        } catch {
            self.error = error.localizedDescription
        }
    }
}
