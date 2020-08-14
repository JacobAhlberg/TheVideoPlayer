//
//  ViewController.swift
//  TheVideoPlayer
//
//  Created by Jacob Ahlberg on 2020-08-07.
//  Copyright © 2020 Knowit Mobile. All rights reserved.
//

import UIKit
import AVFoundation
import AVKit
import MediaPlayer

class ViewController: UIViewController {
    @IBOutlet weak var playerView: PlayerView!
    // For airplay
    @IBOutlet weak var airplayContainerView: UIView!
    // For custom controllers
    @IBOutlet weak var controlView: ControlView!

    // Airplay AVRoutePickerView
    private var routePicker: AVRoutePickerView {
        let routePicker = AVRoutePickerView()
        routePicker.prioritizesVideoDevices = true
        routePicker.frame = .init(x: 0, y: 0, width: 44, height: 44)
        routePicker.tintColor = .white
        routePicker.activeTintColor = #colorLiteral(red: 0.03529411765, green: 0.5176470588, blue: 1, alpha: 1)
        return routePicker
    }

    // To get the current orientation of device
    private var statusBarOrientation: UIInterfaceOrientation {
        get {
            guard let orientation = UIApplication.shared.windows.first?.windowScene?.interfaceOrientation else {
                fatalError("Could not find orientation")
            }
            return orientation
        }
    }
    private var shouldRotate = false
    override var shouldAutorotate: Bool { return shouldRotate }

    var assetPlayer: AssetPlayer!

    // MARK: - Video key value observers

    private var playerTimerControlStatusObserver: NSKeyValueObservation?
    private var playerItemCanStepForwardObserver: NSKeyValueObservation?
    private var playerItemCanStepBackwardObserver: NSKeyValueObservation?
    private var playerItemStatusObserver: NSKeyValueObservation?

    private var timeObserverToken: Any?

    override func viewDidLoad() {
        super.viewDidLoad()
        controlView.delegate = self
        setupAirPlay()
        setupAssetPlayer()
    }

    @IBAction func didPressEnterFullScreenCustom(_ sender: UIButton) {
        shouldRotate.toggle()
        UIDevice.current.setValue(statusBarOrientation == .portrait ? UIInterfaceOrientation.landscapeRight.rawValue :
            UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
        UIViewController.attemptRotationToDeviceOrientation()

        sender.setImage(UIImage(systemName: statusBarOrientation == .portrait ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left"), for: .normal)
        shouldRotate.toggle()
    }


    // MARK: - Setup

    private func setupAssetPlayer() {
        do {
            // Create an AssetPlayer
            assetPlayer = try AssetPlayer()

            /**
            Add/Replace the current player in the `playerView`.
            The `AVPlayer` and `AVPlayerItem` are not a visible objects. Use the `AVPlayerLayer`
            object to manage visual output.
            */
            playerView.player = assetPlayer.player

            /**
             Connect to the handlers. As soon an update occurs the corresponding
             handler will be triggered.
             */
            assetPlayer.onTimeControlStatusUpdate = { [weak self] player in
                guard let self = self else { return }
                /**
                 Configure the image for the `playPauseButton` depending on the
                 players' property `timeControlStatus`.
                 */
                self.controlView.setPlayPauseButtonIcon(with: player)
            }

            assetPlayer.onPeriodicTimeUpdate = { [weak self] (time, player) in
                guard let self = self else { return }
                self.controlView.updateUIForSlider(with: time, player: player)
            }

            assetPlayer.onFastForwardUpdate = { [weak self] playable in
                guard let self = self else { return }
                self.controlView.fastForwardButton.isEnabled = playable

            }

            assetPlayer.onReverseUpdate = { [weak self] playable in
                guard let self = self else { return }
                self.controlView.reverseButton.isEnabled = playable
            }

            assetPlayer.onStatusUpdate = { [weak self] player in
                guard let self = self else { return }
                // Configure the UI for the controlView
                self.controlView.updateUIForControl(with: player)
            }

            // Start session
            try assetPlayer.setupSession()
        } catch {
            print(error)
        }
    }

    // Adding the AVRoutePickerView to the containerView.
    private func setupAirPlay() {
        airplayContainerView.addSubview(routePicker)
    }
}

extension ViewController: ControlDelegate {
    func didPressPlayPause() {
        assetPlayer.play()
    }

    func didPressFastForward() {
        assetPlayer.fastForward()
    }

    func didPressReverse() {
        assetPlayer.reverse()
    }

    func didPressForward() {
        assetPlayer.skipForward(by: 10)
    }

    func didPressRewind() {
        assetPlayer.skipBackward(by: -10)
    }

    func didSlideTimer(with seconds: Double) {
        assetPlayer.adjustTime(with: seconds)
    }
}