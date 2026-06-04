/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// SampleAppsView.swift
//
// Main screen listing available sample apps that demonstrate DAT SDK Display features.
// Each sample shows an icon, title, and description at the top with a "Try it" button
// pinned to the bottom of the screen that sends the display view to the glasses.
//

import SwiftUI

// MARK: - SampleAppItem

enum SampleAppItem: String, CaseIterable, Identifiable {
  case carMaintenance = "car-maintenance"

  var id: String { rawValue }

  var title: String {
    switch self {
    case .carMaintenance: "Flight Tracker"
    }
  }

  var description: String {
    switch self {
    case .carMaintenance:
      "Track your flight with a summary and detailed information."
    }
  }

  var iconName: String {
    switch self {
    case .carMaintenance: "airplane"
    }
  }

  var iconBackground: Color {
    switch self {
    case .carMaintenance: Color(red: 0.10, green: 0.20, blue: 0.45)
    }
  }
}

// MARK: - SampleAppsView

struct SampleAppsView: View {
  var displayViewModel: DisplayViewModel

  private let item: SampleAppItem = .carMaintenance

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: item.iconName)
        .font(.system(size: 32, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 72, height: 72)
        .background(item.iconBackground, in: RoundedRectangle(cornerRadius: 16))
        .padding(.top, 48)

      Text(item.title)
        .font(.title3.weight(.semibold))
        .foregroundStyle(.primary)
        .multilineTextAlignment(.center)

      Text(item.description)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)

      // Preview of the Flight home widget (tappable)
      FlightHomeWidgetPreview { Task { await displayViewModel.sendFlightSummary() } }

      Spacer()

      SwiftUI.Button {
        Task { await sendSample(item) }
      } label: {
        Text("Try it")
          .font(.body.weight(.semibold))
          .foregroundStyle(.white)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 16)
          .background(
            LinearGradient(
              colors: [Color(red: 0.30, green: 0.45, blue: 0.95), Color(red: 0.15, green: 0.25, blue: 0.85)],
              startPoint: .leading,
              endPoint: .trailing
            ),
            in: Capsule()
          )
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 24)
    .padding(.bottom, 16)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .toolbar(.hidden, for: .navigationBar)
  }

  private func sendSample(_ item: SampleAppItem) async {
    switch item {
    case .carMaintenance:
      await displayViewModel.sendFlightSummary()
    }
  }
}

private struct FlightHomeWidgetPreview: View {
  var onTap: () -> Void
  var body: some View {
    Button(action: onTap) {
      HStack(spacing: 12) {
        Image(systemName: "airplane")
          .font(.headline)
          .foregroundStyle(.white)
          .frame(width: 48, height: 48)
          .background(Color.blue, in: RoundedRectangle(cornerRadius: 10))
        VStack(alignment: .leading, spacing: 2) {
          Text("Flight 1056").font(.body)
          Text("LGA → LAX").font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        Image(systemName: "chevron.right").foregroundStyle(.secondary)
      }
      .padding(12)
      .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
    .buttonStyle(.plain)
  }
}

