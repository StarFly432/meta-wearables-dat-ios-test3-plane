// File: DisplayAccess/Samples/CarMaintenanceDisplay.swift

import Foundation
import SwiftUI
import MWDATDisplay

// Namespace providing sample car maintenance displayable content used by DisplayViewModel
enum CarMaintenanceDisplay {
  // Basic data models used to drive the mock content
  struct TutorialStep: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let description: String
  }

  struct Tutorial: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let steps: [TutorialStep]
  }

  // Public sample data referenced by DisplayViewModel
  static let tutorials: [Tutorial] = [
    Tutorial(
      title: "Change Engine Oil",
      steps: [
        TutorialStep(title: "Prepare Tools", description: "Gather wrench, oil pan, new filter, and oil."),
        TutorialStep(title: "Drain Old Oil", description: "Remove drain plug and let oil drain completely."),
        TutorialStep(title: "Replace Filter", description: "Unscrew old filter and install new one."),
        TutorialStep(title: "Add New Oil", description: "Refill engine with manufacturer-recommended oil.")
      ]
    ),
    Tutorial(
      title: "Replace Air Filter",
      steps: [
        TutorialStep(title: "Open Housing", description: "Release clips and open air filter housing."),
        TutorialStep(title: "Swap Filter", description: "Remove old filter and insert new one."),
        TutorialStep(title: "Close Housing", description: "Secure clips and ensure proper seal.")
      ]
    )
  ]

  // MARK: - Displayable Views

  // List of tutorials with a tap handler
  static func tutorialList(onSelect: @escaping (Int) -> Void) -> some View {
    VStack(spacing: 12) {
      Text("Car Maintenance Tutorials").font(.title)
      VStack(spacing: 8) {
        ForEach(Array(tutorials.enumerated()), id: \.offset) { index, tutorial in
          Button(action: { onSelect(index) }) {
            Text(tutorial.title)
          }
        }
      }
    }
    .padding()
  }

  // Tutorial detail with back and start actions
  static func tutorialDetail(
    tutorialIndex: Int,
    onBack: @escaping () -> Void,
    onStart: @escaping () -> Void
  ) -> some View {
    let tutorial = tutorials[safe: tutorialIndex] ?? tutorials[0]
    return VStack(spacing: 12) {
      Text(tutorial.title).font(.title2)
      Text("Steps: \(tutorial.steps.count)")
      HStack(spacing: 12) {
        Button(action: onBack) { Text("Back") }
        Button(action: onStart) { Text("Start") }
      }
    }
    .padding()
  }

  // Single step screen with previous/next actions and a Watch Video action
  static func tutorialStep(
    tutorialIndex: Int,
    stepIndex: Int,
    onPrevious: @escaping () -> Void,
    onNext: @escaping () -> Void,
    onWatchVideo: @escaping () -> Void
  ) -> some View {
    let tutorial = tutorials[safe: tutorialIndex] ?? tutorials[0]
    let step = tutorial.steps[safe: stepIndex] ?? tutorial.steps[0]
    return VStack(spacing: 12) {
      Text(tutorial.title).font(.headline)
      Text("Step \(stepIndex + 1) of \(tutorial.steps.count): \(step.title)")
      Text(step.description).multilineTextAlignment(.leading)
      HStack(spacing: 12) {
        Button(action: onPrevious) { Text("Previous") }
        Button(action: onNext) { Text("Next") }
      }
      Button(action: onWatchVideo) { Text("Watch Video") }
    }
    .padding()
  }

  // Placeholder video view. The DisplayViewModel listens for playback events.
  static func tutorialVideo() -> some View {
    // Using a generic media container with placeholder metadata
    VStack(spacing: 8) {
      Text("Playing Tutorial Video...").font(.headline)
      Text("This is a placeholder video view.")
    }
    .padding()
  }
}

// MARK: - Safe indexing helper
private extension Array {
  subscript(safe index: Int) -> Element? {
    guard indices.contains(index) else { return nil }
    return self[index]
  }
}

