/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// DisplayViewModel.swift
//
// Manages the display session lifecycle: attaching to a display-capable device,
// sending views, and detaching. Uses DSPN's pending action pattern so that
// tapping "play" auto-attaches and sends the view once the display is ready.
//

import MWDATCore
import MWDATDisplay
import Observation
import SwiftUI
import os

@Observable
@MainActor
class DisplayViewModel {
  var isConnected: Bool = false
  var isSending: Bool = false
  var errorMessage: String?
  var requiresDATAppUpdate: Bool = false
  var didFailToStartSession: Bool = false
  
  @ObservationIgnored private let debugLogging = true
  @ObservationIgnored private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "DisplayAccess", category: "DisplayViewModel")
  private func log(_ message: String) {
    if debugLogging {
      print("[DisplayVM] \(message)")
      logger.log("[DisplayVM] \(message)")
    }
  }

  @ObservationIgnored private let wearables: WearablesInterface
  @ObservationIgnored private var deviceSelector: AutoDeviceSelector
  @ObservationIgnored private var deviceSession: DeviceSession?
  @ObservationIgnored private var display: Display?
  @ObservationIgnored private var stateListenerToken: AnyListenerToken?
  @ObservationIgnored private var coreStateTask: Task<Void, Never>?
  @ObservationIgnored private var sessionErrorTask: Task<Void, Never>?
  @ObservationIgnored private var registrationTask: Task<Void, Never>?
  @ObservationIgnored private var displayStateTask: Task<Void, Never>?
  @ObservationIgnored private var displayStateContinuation: AsyncStream<DisplayState>.Continuation?
  @ObservationIgnored private var pendingAction: (() async -> Void)?
  @ObservationIgnored private var isAttaching: Bool = false
  @ObservationIgnored private var isSendingInFlight: Bool = false

  @ObservationIgnored private let instanceID = UUID()
  @ObservationIgnored private var isWearablesReadyForSession: Bool { true } // TODO: Wire this to a real readiness signal from WearablesInterface

  init(wearables: WearablesInterface) {
    self.wearables = wearables
    self.deviceSelector = AutoDeviceSelector(wearables: wearables, filter: { $0.supportsDisplay() })
    observeRegistration()
    log("Initialized DisplayViewModel instanceID=\(instanceID)")
    // Auto-start a demo animation on launch
    Task { @MainActor in
      // Brief delay to allow app launch to settle
      try? await Task.sleep(nanoseconds: 300_000_000)
      await self.sendAnimatedAirplane()
    }
  }

  isolated deinit {
    stateListenerToken = nil
    coreStateTask?.cancel()
    sessionErrorTask?.cancel()
    registrationTask?.cancel()
    displayStateTask?.cancel()
  }

  // MARK: - Registration Observation

  private func observeRegistration() {
    registrationTask = Task { [weak self] in
      guard let wearables = self?.wearables else { return }
      for await state in wearables.registrationStateStream() {
        guard let self, !Task.isCancelled else { return }
        self.log("Registration state changed to \(state). Resetting display session. (instanceID=\(self.instanceID))")
        if state == .available || state == .unavailable {
          await self.resetDisplaySession()
        }
      }
    }
  }

  private func resetDisplaySession() async {
    log("Resetting display session")
    await detachFromDisplay()
    deviceSelector = AutoDeviceSelector(wearables: wearables, filter: { $0.supportsDisplay() })
  }

  // MARK: - Public API

  /// Sends a display view to the glasses. Auto-attaches if not connected;
  /// the view is queued and sent once the display session is ready.
  func send<V: View>(_ view: V) async {
    log("send called. isConnected=\(isConnected), hasDisplay=\(display != nil), instanceID=\(instanceID)")
    let sendID = UUID()
    let viewType = String(describing: V.self)
    log("send(\(viewType)) [\(sendID)]: entry")
    let displayable = DisplayView(view)
    if let display, isConnected {
      log("Sending immediately on connected display [\(sendID)] viewType=\(viewType)")
      await doSend(displayable, on: display)
      return
    }

    log("Queueing pending send action until display is ready [\(sendID)] viewType=\(viewType)")
    // Store as pending action — will fire once display is ready
    let sendableView = displayable
    pendingAction = { [weak self] in
      guard let self else { return }
      await self.log("Pending action set for sendID=\(sendID)")
      await self.log("Executing pending send action [\(sendID)] viewType=\(viewType)")
      guard let cap = self.display else { return }
      await self.doSend(sendableView, on: cap)
    }

    if display == nil {
      log("No display present. Attaching to display... [\(sendID)]")
      await attachToDisplay()
    } else if display != nil && !isConnected {
      log("Display present but not connected. Reattaching... [\(sendID)]")
      await attachToDisplay()
    }
  }

  /// Sends a displayable (non-SwiftUI) view directly to the glasses. Auto-attaches if not connected.
  func send(_ view: some DisplayableView) async {
    log("send(DisplayableView) called. isConnected=\(isConnected), hasDisplay=\(display != nil), instanceID=\(instanceID)")
    let sendID = UUID()
    log("send(DisplayableView) [\(sendID)]: entry")

    if let display, isConnected {
      log("Sending DisplayableView immediately on connected display [\(sendID)]")
      await doSend(view, on: display)
      return
    }

    log("Queueing pending send action until display is ready [\(sendID)] (DisplayableView)")
    let sendableView = view
    pendingAction = { [weak self] in
      guard let self else { return }
      await self.log("Pending action set for sendID=\(sendID) (DisplayableView)")
      await self.log("Executing pending send action [\(sendID)] (DisplayableView)")
      guard let cap = self.display else { return }
      await self.doSend(sendableView, on: cap)
    }

    if display == nil {
      log("No display present. Attaching to display... [\(sendID)] (DisplayableView)")
      await attachToDisplay()
    } else if display != nil && !isConnected {
      log("Display present but not connected. Reattaching... [\(sendID)] (DisplayableView)")
      await attachToDisplay()
    }
  }

  private func doSend(_ view: some DisplayableView, on capability: Display) async {
    log("doSend: attempting to send view (inFlight=\(isSendingInFlight)) (instanceID=\(instanceID))")
    if isSendingInFlight {
      log("doSend: another send is in-flight, skipping this send")
      return
    }
    isSendingInFlight = true
    isSending = true
    defer {
      isSending = false
      isSendingInFlight = false
    }

    do {
      try await capability.send(view)
      self.log("doSend: send completed without throwing")
      self.log("doSend: view sent successfully (inFlight cleared)")
    } catch {
      let message = (error as? DisplayError)?.description ?? error.localizedDescription
      log("doSend error: \(message)")
      errorMessage = message
    }
  }

  // MARK: - Session Management

  func attachToDisplay() async {
    guard (display == nil || isConnected == false) && isAttaching == false else { log("attachToDisplay: guard prevented re-entry (display=\(display != nil), isConnected=\(isConnected), isAttaching=\(isAttaching))"); return }
    // Gate attach on wearables readiness to avoid CoreBluetooth powered-off misuse
    guard isWearablesReadyForSession else {
      log("attachToDisplay: wearables not ready; deferring (instanceID=\(instanceID))")
      return
    }
    log("attachToDisplay: starting attach flow (instanceID=\(instanceID))")
    isAttaching = true

    didFailToStartSession = false

    do {
      let devSession = try wearables.createSession(deviceSelector: deviceSelector)
      log("attachToDisplay: created device session (instanceID=\(instanceID))")
      deviceSession = devSession

      let stateStream = devSession.stateStream()
      let errorStream = devSession.errorStream()
      coreStateTask = Task { [weak self] in
        for await sessionState in stateStream {
          guard let self, !Task.isCancelled else { return }
          switch sessionState {
          case .started:
            self.log("DeviceSession state: started")
            self.requiresDATAppUpdate = false
            self.didFailToStartSession = false
            await self.setupDisplay(on: devSession)
          case .stopping, .stopped:
            self.log("DeviceSession state: \(sessionState)")
            self.isConnected = false
            self.display = nil
          case .starting, .idle, .paused:
            self.log("DeviceSession state: \(sessionState)")
          @unknown default:
            break
          }
        }
      }
      sessionErrorTask = Task { [weak self] in
        for await error in errorStream {
          guard let self, !Task.isCancelled else { return }
          self.log("DeviceSession error: \(error)")
          self.handleSessionError(error)
        }
      }

      log("attachToDisplay: starting device session (instanceID=\(instanceID))")
      try devSession.start()
      isAttaching = false
    } catch DeviceSessionError.datAppOnTheGlassesUpdateRequired {
      log("attachToDisplay: DAT app update required on glasses")
      isAttaching = false
      requiresDATAppUpdate = true
      didFailToStartSession = true
      errorMessage = DeviceSessionError.datAppOnTheGlassesUpdateRequired.localizedDescription
    } catch {
      log("attachToDisplay: failed to create/start session: \(error.localizedDescription)")
      isAttaching = false
      requiresDATAppUpdate = false
      didFailToStartSession = true
      errorMessage = "Failed to create session: \(error.localizedDescription)"
    }
  }

  func clearSessionStartFailure() {
    didFailToStartSession = false
  }

  private func setupDisplay(on devSession: DeviceSession) async {
    log("setupDisplay: preparing display capability (instanceID=\(instanceID))")
    guard display == nil else { return }

    do {
      let capability = try devSession.addDisplay()
      log("setupDisplay: display capability added")
      log("setupDisplay: about to store display reference")

      display = capability
      log("setupDisplay: display reference stored")

      let (stateStream, continuation) = AsyncStream.makeStream(of: DisplayState.self)
      displayStateContinuation = continuation
      stateListenerToken = capability.statePublisher.listen { state in
        continuation.yield(state)
      }

      displayStateTask = Task { [weak self] in
        for await state in stateStream {
          guard let self, !Task.isCancelled else { return }
          switch state {
          case .starting:
            self.log("Display state: starting")
          case .started:
            self.log("Display state: started (pendingAction exists=\(self.pendingAction != nil))")
            self.isConnected = true
            // Execute pending action now that display is ready
            if let action = self.pendingAction {
              self.pendingAction = nil
              await action()
            }
          case .stopping:
            self.log("Display state: stopping")
            self.isConnected = false
          case .stopped:
            self.log("Display state: stopped; cleaning up")
            self.isConnected = false
            self.stateListenerToken = nil
            self.displayStateContinuation?.finish()
            self.displayStateContinuation = nil
            self.display = nil
            self.coreStateTask?.cancel()
            self.coreStateTask = nil
            self.deviceSession?.stop()
            self.deviceSession = nil
          }
        }
      }

      log("setupDisplay: starting display capability")
      await capability.start()
    } catch {
      log("setupDisplay: failed to start display: \(error.localizedDescription)")
      errorMessage = "Failed to start display: \(error.localizedDescription)"
    }
  }

  // MARK: - Test Pattern

  /// Sends a high-contrast, obviously visible test view to verify rendering on the glasses.
  func sendTestPattern() async {
    let testView = AnyView(
      ZStack {
        Color.blue
          .ignoresSafeArea()
        VStack(spacing: 16) {
          Text("Hello Glasses")
            .font(.system(size: 44, weight: .bold))
            .foregroundStyle(.white)
          Text("If you can read this, display rendering works.")
            .font(.headline)
            .foregroundStyle(.white.opacity(0.9))
        }
        .padding()
      }
    )
    await send(testView)
  }

  // MARK: - Car Maintenance

  func sendCarMaintenanceTutorialList() async {
    await send(
      AnyView(
        CarMaintenanceDisplay.tutorialList { [weak self] index in
          Task { @MainActor in
            await self?.sendCarMaintenanceTutorialDetail(tutorialIndex: index)
          }
        }
      )
    )
  }

  func sendCarMaintenanceTutorialDetail(tutorialIndex: Int) async {
    await send(
      AnyView(
        CarMaintenanceDisplay.tutorialDetail(
          tutorialIndex: tutorialIndex,
          onBack: { [weak self] in
            Task { @MainActor in
              await self?.sendCarMaintenanceTutorialList()
            }
          },
          onStart: { [weak self] in
            Task { @MainActor in
              await self?.sendCarMaintenanceTutorialStep(tutorialIndex: tutorialIndex, stepIndex: 0)
            }
          }
        )
      )
    )
  }

  func sendTutorialVideo(tutorialIndex: Int, stepIndex: Int) async {
    await send(AnyView(CarMaintenanceDisplay.tutorialVideo()))
    display?.onPlaybackEvent = { [weak self] event in
      if event.type == .ended || event.type == .stopped {
        Task { @MainActor [weak self] in
          self?.display?.onPlaybackEvent = nil
          await self?.sendCarMaintenanceTutorialStep(
            tutorialIndex: tutorialIndex,
            stepIndex: stepIndex
          )
        }
      }
    }
  }

  func sendCarMaintenanceTutorialStep(tutorialIndex: Int, stepIndex: Int) async {
    let isLastStep = stepIndex == CarMaintenanceDisplay.tutorials[tutorialIndex].steps.count - 1
    await send(
      AnyView(
        CarMaintenanceDisplay.tutorialStep(
          tutorialIndex: tutorialIndex,
          stepIndex: stepIndex,
          onPrevious: { [weak self] in
            Task { @MainActor in
              if stepIndex == 0 {
                await self?.sendCarMaintenanceTutorialDetail(tutorialIndex: tutorialIndex)
              } else {
                await self?.sendCarMaintenanceTutorialStep(
                  tutorialIndex: tutorialIndex,
                  stepIndex: stepIndex - 1
                )
              }
            }
          },
          onNext: { [weak self] in
            Task { @MainActor in
              if isLastStep {
                await self?.sendCarMaintenanceTutorialList()
              } else {
                await self?.sendCarMaintenanceTutorialStep(
                  tutorialIndex: tutorialIndex,
                  stepIndex: stepIndex + 1
                )
              }
            }
          },
          onWatchVideo: { [weak self] in
            Task { @MainActor in
              await self?.sendTutorialVideo(tutorialIndex: tutorialIndex, stepIndex: stepIndex)
            }
          }
        )
      )
    )
  }

  func detachFromDisplay() async {
    log("Detaching from display and cleaning up session")
    stateListenerToken = nil
    displayStateContinuation?.finish()
    displayStateContinuation = nil
    displayStateTask?.cancel()
    displayStateTask = nil
    await display?.stop()
    display = nil
    coreStateTask?.cancel()
    coreStateTask = nil
    sessionErrorTask?.cancel()
    sessionErrorTask = nil
    deviceSession?.stop()
    deviceSession = nil
    isConnected = false
  }

  private func handleSessionError(_ error: DeviceSessionError) {
    log("handleSessionError: \(error)")
    requiresDATAppUpdate = error == .datAppOnTheGlassesUpdateRequired
    didFailToStartSession = true
    errorMessage = error.localizedDescription
  }

  // MARK: - Flight Display

  func sendFlightSummary() async {
    await send(
      FlightDisplay.flightSummary(onShowDetails: { [weak self] in
        Task { @MainActor in
          await self?.sendFlightDetails()
        }
      })
    )
  }

  func sendFlightDetails() async {
    await send(
      FlightDisplay.flightDetails(onBack: { [weak self] in
        Task { @MainActor in
          await self?.sendFlightSummary()
        }
      })
    )
  }

  func sendFlightHomeWidget() async {
    await send(
      FlightDisplay.homeWidget(onTap: { [weak self] in
        Task { @MainActor in
          await self?.sendFlightSummary()
        }
      })
    )
  }

  // MARK: - Airplane Demo

  /// Shows a simple airplane image on the glasses. Uses SF Symbol if available, otherwise looks for an asset named "airplane".
  func sendAirplaneImage() async {
    let view = AnyView(
      ZStack {
        // Neutral background to ensure visibility on the display
        Color.black.ignoresSafeArea()
        VStack(spacing: 24) {
          // Prefer SF Symbol if present
          if UIImage(systemName: "airplane") != nil {
            Image(systemName: "airplane")
              .resizable()
              .scaledToFit()
              .frame(width: 240, height: 240)
              .foregroundStyle(.white)
          } else {
            // Fallback to an asset named "airplane" if provided by the app
            Image("airplane")
              .resizable()
              .scaledToFit()
              .frame(width: 240, height: 240)
          }
          Text("Airplane")
            .font(.title.bold())
            .foregroundStyle(.white.opacity(0.9))
        }
        .padding()
      }
    )
    await send(view)
  }

  /// Demonstrates a simple animated airplane fly-by using SwiftUI animation.
  /// No external files required if you use the SF Symbol. If you want a custom image, add it to Assets as "airplane".
  func sendAnimatedAirplane() async {
    struct AnimatedAirplaneView: View {
      @State private var xOffset: CGFloat = -400
      var body: some View {
        ZStack {
          Color.black.ignoresSafeArea()
          GeometryReader { proxy in
            let width = proxy.size.width
            let symbolAvailable = UIImage(systemName: "airplane") != nil
            Group {
              if symbolAvailable {
                Image(systemName: "airplane")
                  .resizable()
                  .scaledToFit()
                  .foregroundStyle(.white)
              } else {
                Image("airplane")
                  .resizable()
                  .scaledToFit()
              }
            }
            .frame(width: 160, height: 160)
            .offset(x: xOffset, y: 0)
            .onAppear {
              withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                xOffset = width / 2 - 40 // fly to the right edge-ish
              }
            }
          }
        }
      }
    }

    await send(AnimatedAirplaneView())
  }
}

