//
//  AssetPlayer.swift
//  TheVideoPlayer
//
//  Created by Jacob Ahlberg on 2020-08-12.
//  Copyright © 2020 Knowit Mobile. All rights reserved.
//

import Foundation
import AVFoundation
import MediaPlayer

class AssetPlayer {

    enum PlayerState {
        case playing
        case stopped
        case paused
    }

    let player: AVPlayer
    
    private let behavior: NowPlayable
//    private var playerState: PlayerState = .stopped
    private let allMetaData: [NowPlayableMetaData]
    private let playerItems: [AVPlayerItem]

    // Observers
    private var playerTimerControlStatusObserver: NSKeyValueObservation?
    private var playerItemCanStepForwardObserver: NSKeyValueObservation?
    private var playerItemCanStepBackwardObserver: NSKeyValueObservation?
    private var playerItemStatusObserver: NSKeyValueObservation?
    private var timeObserverToken: Any?

    // Handlers
    var onTimeControlStatusUpdate: ((AVPlayer) -> Void)?
    var onPeriodicTimeUpdate: ((CMTime, AVPlayer) -> Void)?
    var onFastForwardUpdate: ((_ playable: Bool) -> Void)?
    var onReverseUpdate: ((_ playable: Bool) -> Void)?
    var onStatusUpdate: ((AVPlayer) -> Void)?


    // Initialize player with the configurations
    init(configuration: Configuration = PlayerConfiguration.shared) throws {
        // Set the configuration playable behavior.
        behavior = configuration.behavior

        // Get the metaData from the configuration
        allMetaData = configuration.assets.map { $0.metaData }

        // Get the assets from the configuration and create AVPlayerItems from the urlAssets.
        playerItems = configuration.assets.map { AVPlayerItem(asset: $0.urlAsset) }
        guard let firstItem = playerItems.first else {
            throw PlayerError.noAssetFound
        }

        // Create a AVPlayer and configure it for external playback.
        self.player = AVPlayer(playerItem: firstItem)
        self.player.allowsExternalPlayback = configuration.allowsExternalPlayback

        var registeredCommands: [NowPlayableCommand] = []
        configuration.commandCollections.forEach({
            registeredCommands.append(contentsOf: $0.commands.compactMap({ $0.command }))
        })

        // Configure player for Now Playing info and Remote Command Center behaviors.
        try behavior.handleConfiguration(commands: registeredCommands,
                                         disableCommands: [],
                                         commandHandler: handleCommand(command:event:),
                                         interruptionHandler: handleInterruption(interuption:))
    }
    /**
     Removes all current handlers
     */
    func removeAllHandlers() {
        onTimeControlStatusUpdate = nil
        onPeriodicTimeUpdate = nil
        onFastForwardUpdate = nil
        onReverseUpdate = nil
        onStatusUpdate = nil
    }

    func setupSession() throws {
        // Make sure there's a current item
        guard player.currentItem != nil else {
            throw PlayerError.noAssetFound
        }
        // Setup Now Playing session
        try behavior.handleNowPlayingSessionStart()
        // Creates observers
        addObservers()
        // Starts the player
        play()
    }

    private func addObservers() {
        /**
        Add an observer to toggle between pause/play to reflect
        the playback state of the AVPlayer's `timeControlStatus` property.
        */
        playerTimerControlStatusObserver = player.observe(\AVPlayer.timeControlStatus, options: [.initial, .new]) { [weak self] (player, _) in
            guard let self = self else { return }
            DispatchQueue.main.async { self.onTimeControlStatusUpdate?(player) }
        }

        let interval = CMTime(value: 1, timescale: 2)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main, using: { [weak self] (time) in
            guard let self = self else { return }
            DispatchQueue.main.async { self.onPeriodicTimeUpdate?(time, self.player) }
        })

        /**
         Create observeres to the players' properties `canStepForward` and `canStepBackward` to
         enable the corresponding buttons.
         */
        playerItemCanStepForwardObserver = player.observe(\AVPlayer.currentItem?.canPlayFastForward, options: [.initial, .new]) { [weak self] (player, _) in
            guard let self = self else { return }
            DispatchQueue.main.async { self.onFastForwardUpdate?(player.currentItem?.canPlayFastForward ?? false)}
        }

        playerItemCanStepBackwardObserver = player.observe(\AVPlayer.currentItem?.canPlayReverse, options: [.initial, .new]) { [weak self] (player, _) in
            guard let self = self else { return }
            DispatchQueue.main.async { self.onReverseUpdate?(player.currentItem?.canPlayReverse ?? false)}
        }

        /**
         Create an observer on the player's item property `status` to observe
         state changes as they occurs.
         */
        playerItemStatusObserver = player.observe(\AVPlayer.currentItem?.status, options: [.initial, .new], changeHandler: { [weak self] (player, _) in
            guard let self = self else { return  }
            DispatchQueue.main.async { self.onStatusUpdate?(self.player) }
        })
    }

    // MARK: - Remote commands

    private func handleCommand(command: NowPlayableCommand, event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        switch command {
        case .play: play()
        case .pause: pause()
        case .skipForward:
            guard let event = event as? MPSkipIntervalCommandEvent else {
                return .commandFailed
            }
            skipForward(by: event.interval)
        case .skipBackward:
            guard let event = event as? MPSkipIntervalCommandEvent else {
                return .commandFailed
            }
            skipBackward(by: event.interval)
        }
        return .success
    }

    // MARK: - Interuptions

    private func handleInterruption(interuption: NowPlayableInterruption) {
        switch interuption {
        case .began: ()
        case .ended( _): ()
        case .failed( _): ()
        }
    }

    // MARK: - Now Playing information

    private func handlePlayerItemChange() {
//        guard playerState != .stopped else { return }
        guard player.timeControlStatus != .paused else { return }

        // Find the item and its' index
        guard let item = player.currentItem else {
            #warning("handle opt out")
            return
        }
        guard let index = playerItems.firstIndex(where: { $0 == item }) else { return }

        // Update Now Playing information
        behavior.handleNowPlayableItemChange(metadata: allMetaData[index])
    }

    // MARK: - Helper functions
    
    /**
     Returns a new time depending on if jumping forward or rewinding back 10 seconds.

     - Parameter direction: Chooses between either forward(+10 seconds) or rewind (-10 seconds).
     - Returns: An updated time which either will be 10 seconds forward or rewind of current time.
     */
    private func getNewTime(by interval: TimeInterval) -> CMTime {
        let currentTime = player.currentItem?.currentTime() ?? .zero
        let currentTimeInSecondsPlusDirection = CMTimeGetSeconds(currentTime).advanced(by: interval)
        return CMTime(value: CMTimeValue(currentTimeInSecondsPlusDirection), timescale: 1)
    }
}

// MARK: - Playback controls

extension AssetPlayer {
    func play() {
        switch player.timeControlStatus {
        case .paused:
            /**
             If the `currentItem` already has reached its end time, then revert back
             to the beginning
             */
            if (player.currentItem?.currentTime() ?? .zero) >= (player.currentItem?.duration ?? .zero) {
                player.currentItem?.seek(to: .zero, completionHandler: nil)
            }
            player.play()

            handlePlayerItemChange()
        default: player.pause()
        }
    }

    func pause() {
        // If the player is currently playing, then pause.
        player.pause()
    }

    func skipForward(by interval: TimeInterval) {
        player.seek(to: getNewTime(by: interval))
    }

    func skipBackward(by interval: TimeInterval) {
        player.seek(to: getNewTime(by: interval))
    }

    func reverse() {
        // Play reverse no faster than -2
        player.rate = max(player.rate - 2, -2)
    }

    func fastForward() {
        /**
        If the `currentItem` already has reached its end time, then revert back
        to the beginning
        */
        if (player.currentItem?.currentTime() ?? .zero) >= (player.currentItem?.duration ?? .zero) {
            player.currentItem?.seek(to: .zero, completionHandler: nil)
        }
        // Play fast forward no faster than 2
        player.rate = min(player.rate + 2, 2)
    }

    func adjustTime(with seconds: Double) {
        let newTime = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: newTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }
}
