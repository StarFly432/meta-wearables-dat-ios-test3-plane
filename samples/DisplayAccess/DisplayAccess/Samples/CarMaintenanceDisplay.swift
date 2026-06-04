/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// FlightDisplay.swift
//
// Display views for Airline travel — summary and detailed flight information for phone/home and glasses.
//

import MWDATDisplay
import Foundation

struct FlightSegment {
  let origin: String
  let destination: String
  let flightNumber: String
}

struct FlightInfo {
  let eTicketNumber: String
  let departureDateText: String
  let confirmationCode: String
  let airline: String
  let operatedBy: String
  let primaryFlightNumber: String
  let gate: String
  let origin: String
  let destination: String
  let segments: [FlightSegment]
  let boardingDate: Date
  let baggageClaim: String?
  let airplaneImageUri: String?
  let airplaneIconUri: String?
}

private func countdownString(to date: Date) -> String {
  let now = Date()
  let remaining = max(0, Int(date.timeIntervalSince(now)))
  let hours = remaining / 3600
  let minutes = (remaining % 3600) / 60
  if hours > 0 {
    return "Boards in \(hours)h \(minutes)m"
  } else {
    return "Boards in \(minutes)m"
  }
}

enum FlightDisplay {
  static let sampleFlight: FlightInfo = {
    // Assume example local time today at 12:56pm takeoff and boarding 30 minutes before
    let calendar = Calendar.current
    var comps = calendar.dateComponents([.year, .month, .day], from: Date())
    comps.hour = 12
    comps.minute = 26 // 12:26pm boarding for 12:56pm takeoff
    let boarding = calendar.date(from: comps) ?? Date().addingTimeInterval(60*30)

    return FlightInfo(
      eTicketNumber: "0017430684429",
      departureDateText: "Monday, June 15",
      confirmationCode: "NHKSCF",
      airline: "American Airlines",
      operatedBy: "American Airlines",
      primaryFlightNumber: "1056",
      gate: "B3",
      origin: "LGA",
      destination: "LAX",
      segments: [
        FlightSegment(origin: "LGA", destination: "DFW", flightNumber: "1056"),
        FlightSegment(origin: "DFW", destination: "LAX", flightNumber: "2766")
      ],
      boardingDate: boarding,
      baggageClaim: "Baggage Claim Carousel 5 (subject to change)",
      airplaneImageUri: "https://www.facebook.com/assets/wearables_dat_display/airplane.png",
      airplaneIconUri: "https://www.facebook.com/assets/wearables_dat_display/airplane_square.png"
    )
  }()

  // Home/phone compact widget
  static func homeWidget(onTap: @escaping @Sendable () -> Void) -> FlexBox {
    let f = sampleFlight
    return FlexBox(direction: .row, spacing: 12, crossAlignment: .center) {
      if let icon = f.airplaneIconUri {
        FlexBox(direction: .column) {
          Image(uri: icon, sizePreset: .fill, cornerRadius: .medium)
        }
        .flexGrow(1)
      }
      FlexBox(direction: .column, spacing: 2) {
        Text("Flight \(f.primaryFlightNumber)", style: .body)
        Text("\(f.origin) → \(f.destination)", style: .meta, color: .secondary)
      }
      .flexGrow(7)
    }
    .padding(16)
    .background(.card)
    .onTap(onTap)
  }

  // Glasses Screen 1: Summary with Flight No., time until boarding, and Gate
  static func flightSummary(onShowDetails: @escaping @Sendable () -> Void) -> FlexBox {
    let f = sampleFlight
    let countdown = countdownString(to: f.boardingDate)

    return FlexBox(direction: .column, spacing: 12) {
      FlexBox(direction: .column, spacing: 8) {
        if let image = f.airplaneImageUri {
          Image(uri: image, sizePreset: .fill, cornerRadius: .medium)
        }
        Text("Flight \(f.primaryFlightNumber)", style: .heading)
        Text(countdown, style: .meta, color: .secondary)
        Text("Gate \(f.gate)", style: .body)
      }
      .padding(24)
      .background(.card)

      FlexBox(direction: .row, spacing: 8, alignment: .center, crossAlignment: .center) {
        Button(label: "More details", onClick: onShowDetails)
      }
    }
  }

  // Glasses Screen 2: Detailed flight information
  static func flightDetails(onBack: @escaping @Sendable () -> Void) -> FlexBox {
    let f = sampleFlight

    return FlexBox(direction: .column, spacing: 12) {
      FlexBox(direction: .column, spacing: 6) {
        if let image = f.airplaneImageUri {
          Image(uri: image, sizePreset: .fill, cornerRadius: .medium)
        }
        Text("American Airlines", style: .meta, color: .secondary)
        Text("LGA → DFW → LAX", style: .body)
      }
      .padding(24)
      .background(.card)

      FlexBox(direction: .column, spacing: 8) {
        Text("E-ticket number", style: .meta, color: .secondary)
        Text(f.eTicketNumber, style: .body)

        Text("Departure date", style: .meta, color: .secondary)
        Text(f.departureDateText, style: .body)

        Text("Airline booking confirmation", style: .meta, color: .secondary)
        Text(f.confirmationCode, style: .body)

        Text("Airline", style: .meta, color: .secondary)
        Text(f.airline, style: .body)

        Text("Flight No.", style: .meta, color: .secondary)
        Text(f.primaryFlightNumber, style: .body)

        Text("Operated by", style: .meta, color: .secondary)
        Text(f.operatedBy, style: .body)

        Text("Routing", style: .meta, color: .secondary)
        for seg in f.segments {
          Text("\(seg.origin) → \(seg.destination) • \(seg.flightNumber)", style: .body)
        }

        if let bag = f.baggageClaim {
          Text("Baggage claim", style: .meta, color: .secondary)
          Text(bag, style: .body)
        }
      }
      .padding(24)
      .background(.card)

      FlexBox(direction: .row, spacing: 8, alignment: .center, crossAlignment: .center) {
        Button(label: "Back", onClick: onBack)
      }
    }
  }
}

