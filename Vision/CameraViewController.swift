//
//  SpeechRecognizer.swift
//  Vision
//
//  Created by Zak Wegweiser on 12/2/17.
//  Copyright © 2017 Apple. All rights reserved.
//

import UIKit
import AVFoundation
import MediaPlayer

class CameraViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate, AVCapturePhotoCaptureDelegate {
	// MARK: View Controller Life Cycle
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		// Disable UI. The UI is enabled if and only if the session starts running.
		sessionPresetsButton.isEnabled = false
		zoomSlider.isEnabled = false
		
		// Set up the video preview view.
		previewView.session = session
		
		/*
			Check video authorization status. Video access is required and audio
			access is optional. If audio access is denied, audio is not recorded
			during movie recording.
		*/
		switch AVCaptureDevice.authorizationStatus(for: .video) {
			case .authorized:
				// The user has previously granted access to the camera.
				break
			
			case .notDetermined:
				/*
					The user has not yet been presented with the option to grant
					video access. We suspend the session queue to delay session
					setup until the access request has completed.
				*/
				sessionQueue.suspend()
				AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
					if !granted {
						self.setupResult = .notAuthorized
					}
					self.sessionQueue.resume()
				})
		
			default:
				// The user has previously denied access.
				setupResult = .notAuthorized
		}
		
		/*
			Setup the capture session.
			In general it is not safe to mutate an AVCaptureSession or any of its
			inputs, outputs, or connections from multiple threads at the same time.
		
			Why not do all of this on the main queue?
			Because AVCaptureSession.startRunning() is a blocking call which can
			take a long time. We dispatch session setup to the sessionQueue so
			that the main queue isn't blocked, which keeps the UI responsive.
		*/
		sessionQueue.async {
			self.configureSession()
		}
        
        // Listen for audio button
        listenVolumeButton()
        NotificationCenter.default.addObserver(self, selector: #selector(listenVolumeButton), name: .UIApplicationWillEnterForeground, object: nil)
        
        // Ask for speech permissions
        speechRecognizer.initialize()
        
        // Register to receive notification in your class
        NotificationCenter.default.addObserver(self, selector: #selector(decipherVoice(_:)), name: NSNotification.Name(rawValue: "DoneListening"), object: nil)
	}
	
	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		
		sessionQueue.async {
			switch self.setupResult {
				case .success:
					// Only setup observers and start the session running if setup succeeded.
					self.addObservers()
					self.session.startRunning()
					self.isSessionRunning = self.session.isRunning
				
				case .notAuthorized:
					DispatchQueue.main.async {
						let changePrivatySetting = "Sight doesn't have permission to use the camera, please change privacy settings"
						let message = NSLocalizedString(changePrivatySetting, comment: "Alert message when the user has denied access to the camera")
						let	alertController = UIAlertController(title: "Sight", message: message, preferredStyle: .alert)
						alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil))
						alertController.addAction(UIAlertAction(title: NSLocalizedString("Settings",
						                                                                 comment: "Alert button to open Settings"),
						                                                                 style: .`default`, handler: { _ in
							UIApplication.shared.open(URL(string: UIApplicationOpenSettingsURLString)!, options: [:], completionHandler: nil)
						}))
						
						self.present(alertController, animated: true, completion: nil)
					}
				
				case .configurationFailed:
					DispatchQueue.main.async {
						let alertMsg = "Unable to capture media"
						let message = NSLocalizedString(alertMsg, comment: "Alert message when something goes wrong during capture session configuration")
						let alertController = UIAlertController(title: "AVCamBarcode", message: message, preferredStyle: .alert)
						alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil))
						
						self.present(alertController, animated: true, completion: nil)
					}
			}
		}
        
    }
	
	override func viewWillDisappear(_ animated: Bool) {
		sessionQueue.async {
			if self.setupResult == .success {
				self.session.stopRunning()
				self.isSessionRunning = self.session.isRunning
				self.removeObservers()
			}
		}
		
		super.viewWillDisappear(animated)
	}
	
    override var shouldAutorotate: Bool {
		// Do not allow rotation if the region of interest is being resized.
		return !previewView.isResizingRegionOfInterest
	}
	
	override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
		super.viewWillTransition(to: size, with: coordinator)
		
		if let videoPreviewLayerConnection = previewView.videoPreviewLayer.connection {
			let deviceOrientation = UIDevice.current.orientation
			guard let newVideoOrientation = AVCaptureVideoOrientation(deviceOrientation: deviceOrientation),
				deviceOrientation.isPortrait || deviceOrientation.isLandscape else {
				return
			}
			
			videoPreviewLayerConnection.videoOrientation = newVideoOrientation
			
			/*
				When we transition to a new size, we need to recalculate the preview
				view's region of interest rect so that it stays in the same
				position relative to the camera.
			*/
			coordinator.animate(alongsideTransition: { context in
				
					let newRegionOfInterest = self.previewView.videoPreviewLayer.layerRectConverted(fromMetadataOutputRect: self.metadataOutput.rectOfInterest)
					self.previewView.setRegionOfInterestWithProposedRegionOfInterest(newRegionOfInterest)
				},
				completion: { context in
					
					// Remove the old metadata object overlays.
					self.removeMetadataObjectOverlayLayers()
				}
			)
		}
	}
	
	// MARK: Session Management
	
	private enum SessionSetupResult {
		case success
		case notAuthorized
		case configurationFailed
	}
	
	private let session = AVCaptureSession()
	
	private var isSessionRunning = false
	
	private let sessionQueue = DispatchQueue(label: "session queue") // Communicate with the session and other session objects on this queue.
	
	private var setupResult: SessionSetupResult = .success
	
	var videoDeviceInput: AVCaptureDeviceInput!
    
    let photoOutput = AVCapturePhotoOutput()
    
    let speechRecognizer = SpeechRecognizer()
	
	@IBOutlet private var previewView: PreviewView!
	
	// Call this on the session queue.
	private func configureSession() {
		if self.setupResult != .success {
			return
		}
		
		session.beginConfiguration()
		
		// Add video input.
		do {
            var defaultVideoDevice: AVCaptureDevice?
			
			// Choose the back wide angle camera if available, otherwise default to the front wide angle camera.
			if let backCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
				defaultVideoDevice = backCameraDevice
			} else if let frontCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
				// Default to the front wide angle camera if the back wide angle camera is unavailable.
				defaultVideoDevice = frontCameraDevice
			} else {
				defaultVideoDevice = nil
			}
			
			guard let videoDevice = defaultVideoDevice else {
				print("Could not get video device")
				setupResult = .configurationFailed
				session.commitConfiguration()
				return
			}
            
            // Add photo output.
            if session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
                
                photoOutput.isHighResolutionCaptureEnabled = true
                photoOutput.isLivePhotoCaptureEnabled = photoOutput.isLivePhotoCaptureSupported
            } else {
                print("Could not add photo output to the session")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
			
			let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
			
			if session.canAddInput(videoDeviceInput) {
				session.addInput(videoDeviceInput)
				self.videoDeviceInput = videoDeviceInput
				
				DispatchQueue.main.async {
					/*
						Why are we dispatching this to the main queue?
						Because AVCaptureVideoPreviewLayer is the backing layer for PreviewView and UIView
						can only be manipulated on the main thread.
						Note: As an exception to the above rule, it is not necessary to serialize video orientation changes
						on the AVCaptureVideoPreviewLayer’s connection with other session manipulation.
					
						Use the status bar orientation as the initial video orientation. Subsequent orientation changes are
						handled by CameraViewController.viewWillTransition(to:with:).
					*/
					let statusBarOrientation = UIApplication.shared.statusBarOrientation
					var initialVideoOrientation: AVCaptureVideoOrientation = .portrait
					if statusBarOrientation != .unknown {
						if let videoOrientation = AVCaptureVideoOrientation(interfaceOrientation: statusBarOrientation) {
							initialVideoOrientation = videoOrientation
						}
					}
					
					self.previewView.videoPreviewLayer.connection!.videoOrientation = initialVideoOrientation
				}
			} else {
				print("Could not add video device input to the session")
				setupResult = .configurationFailed
				session.commitConfiguration()
				return
			}
		} catch {
			print("Could not create video device input: \(error)")
			setupResult = .configurationFailed
			session.commitConfiguration()
			return
		}
		
		// Add metadata output.
		if session.canAddOutput(metadataOutput) {
			session.addOutput(metadataOutput)
			
			// Set this view controller as the delegate for metadata objects.
			metadataOutput.setMetadataObjectsDelegate(self, queue: metadataObjectsQueue)
			metadataOutput.metadataObjectTypes = metadataOutput.availableMetadataObjectTypes // Use all metadata object types by default.
			
			/*
				Set an inital rect of interest that is 80% of the view's shortest side
				and 25% of the longest side. This means that the region of interest will
				appear in the same spot regardless of whether the app starts in portrait
				or landscape.
			*/
			let width = 1.0
			let height = 1.0
			let x = (1.0 - width) / 2.0
			let y = (1.0 - height) / 2.0
			let initialRectOfInterest = CGRect(x: x, y: y, width: width, height: height)
			metadataOutput.rectOfInterest = initialRectOfInterest

			DispatchQueue.main.async {
				let initialRegionOfInterest = self.previewView.videoPreviewLayer.layerRectConverted(fromMetadataOutputRect: initialRectOfInterest)
				self.previewView.setRegionOfInterestWithProposedRegionOfInterest(initialRegionOfInterest)
			}
		} else {
			print("Could not add metadata output to the session")
			setupResult = .configurationFailed
			session.commitConfiguration()
			return
		}
		
		session.commitConfiguration()
	}

	private let metadataOutput = AVCaptureMetadataOutput()
	
	private let metadataObjectsQueue = DispatchQueue(label: "metadata objects queue", attributes: [], target: nil)
	
	@IBOutlet private var sessionPresetsButton: UIButton!
	
	@IBAction private func capturePhoto() {
        let photoSettings = AVCapturePhotoSettings()
        photoSettings.isHighResolutionPhotoEnabled = true
        if self.videoDeviceInput.device.isFlashAvailable {
            photoSettings.flashMode = .off
        }
        if !photoSettings.availablePreviewPhotoPixelFormatTypes.isEmpty {
            photoSettings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: photoSettings.availablePreviewPhotoPixelFormatTypes.first!]
        }

        //playSoundToCancelShutter()
        //print(currentCount)
        photoOutput.capturePhoto(with: photoSettings, delegate: self)
	}
    
    var killProcess = false
    @IBAction private func capturePhoto2() {
        currentCount = 2
        self.audioResponse(withText: "Say hi to Nathanial Ostrer, he's looking happy!", andSpeed: 0.50)
        currentName = "Nathanial Ostrer"
        self.killProcess = true
        //self.speechRecognizer.startRecording()
    }
    
    @IBAction private func capturePhoto3() {
        currentCount = 2
        self.audioResponse(withText: "Say hi to Nathanial Ostrer", andSpeed: 0.50)
        currentName = "Nathanial Ostrer"
        self.killProcess = true
    }
    
    @IBAction private func capturePhoto4() {
        currentCount = 2
        self.audioResponse(withText: "Say hi to Liang Gao, he's looking sad", andSpeed: 0.50)
        currentName = "Liang Gao"
        self.killProcess = true
    }
    
    @IBAction private func capturePhoto5() {
        currentCount = 2
        self.audioResponse(withText: "Say hi to Liang Gao", andSpeed: 0.50)
        currentName = "Liang Gao"
        self.killProcess = true
    }
    
    /*func playSoundToCancelShutter() {
        var player: AVAudioPlayer?
        guard let url = Bundle.main.url(forResource: "photoShutter2", withExtension: "caf") else { return }
        
        do {
            try AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayback)
            try AVAudioSession.sharedInstance().setActive(true)
            
            
            
            /* The following line is required for the player to work on iOS 11. Change the file type accordingly*/
            player = try AVAudioPlayer(contentsOf: url, fileTypeHint: AVFileType.mp3.rawValue)
            
            /* iOS 10 and earlier require the following line:
             player = try AVAudioPlayer(contentsOf: url, fileTypeHint: AVFileTypeMPEGLayer3) */
            
            guard let player = player else { return }
            
            player.play()
            
        } catch let error {
            print(error.localizedDescription)
        }
    }*/
	
	// MARK: Device Configuration
	
	@IBOutlet private var cameraUnavailableLabel: UILabel!
	
	private let videoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified)
	
	@IBAction private func changeCamera() {
		sessionPresetsButton.isEnabled = false
		zoomSlider.isEnabled = false
		
		// Remove the metadata overlay layers, if any.
		removeMetadataObjectOverlayLayers()
		
		DispatchQueue.main.async {
			let currentVideoDevice = self.videoDeviceInput.device
			let currentPosition = currentVideoDevice.position
			
			let preferredPosition: AVCaptureDevice.Position
			
			switch currentPosition {
				case .unspecified, .front:
					preferredPosition = .back
				
				case .back:
					preferredPosition = .front
			}
			
			let devices = self.videoDeviceDiscoverySession.devices
			let newVideoDevice = devices.first(where: { $0.position == preferredPosition })
			
            if let videoDevice = newVideoDevice {
				do {
					let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
					
					self.session.beginConfiguration()
					
					// Remove the existing device input first, since using the front and back camera simultaneously is not supported.
					self.session.removeInput(self.videoDeviceInput)
					
					/*
						When changing devices, a session preset that may be supported
						on one device may not be supported by another. To allow the
						user to successfully switch devices, we must save the previous
						session preset, set the default session preset (High), and
						attempt to restore it after the new video device has been
						added. For example, the 4K session preset is only supported
						by the back device on the iPhone 6s and iPhone 6s Plus. As a
						result, the session will not let us add a video device that
						does not support the current session preset.
					*/
					let previousSessionPreset = self.session.sessionPreset
					self.session.sessionPreset = .high
					
					if self.session.canAddInput(videoDeviceInput) {
						self.session.addInput(videoDeviceInput)
						self.videoDeviceInput = videoDeviceInput
					} else {
						self.session.addInput(self.videoDeviceInput)
					}
					
					// Restore the previous session preset if we can.
					if self.session.canSetSessionPreset(previousSessionPreset) {
						self.session.sessionPreset = previousSessionPreset
					}
					
					self.session.commitConfiguration()
				} catch {
					print("Error occured while creating video device input: \(error)")
				}
			}
			
			DispatchQueue.main.async {
				self.sessionPresetsButton.isEnabled = true
				self.zoomSlider.isEnabled = true
				self.zoomSlider.maximumValue = Float(min(self.videoDeviceInput.device.activeFormat.videoMaxZoomFactor, CGFloat(8.0)))
				self.zoomSlider.value = Float(self.videoDeviceInput.device.videoZoomFactor)
			}
		}
	}
	
	@IBOutlet private var zoomSlider: UISlider!
	
	@IBAction private func zoomCamera(with zoomSlider: UISlider) {
		do {
			try videoDeviceInput.device.lockForConfiguration()
			videoDeviceInput.device.videoZoomFactor = CGFloat(zoomSlider.value)
			videoDeviceInput.device.unlockForConfiguration()
		} catch {
			print("Could not lock for configuration: \(error)")
		}
	}
	
	// MARK: KVO and Notifications
	
	private var keyValueObservations = [NSKeyValueObservation]()
	
	private func addObservers() {
		var keyValueObservation: NSKeyValueObservation
		
		keyValueObservation = session.observe(\.isRunning, options: .new) { _, change in
			guard let isSessionRunning = change.newValue else { return }
			
			DispatchQueue.main.async {
				self.sessionPresetsButton.isEnabled = isSessionRunning
				//self.cameraButton.isEnabled = isSessionRunning && self.videoDeviceDiscoverySession.devices.count > 1
				self.zoomSlider.isEnabled = isSessionRunning
				self.zoomSlider.maximumValue = Float(min(self.videoDeviceInput.device.activeFormat.videoMaxZoomFactor, CGFloat(8.0)))
				self.zoomSlider.value = Float(self.videoDeviceInput.device.videoZoomFactor)
				
				/*
					After the session stops running, remove the metadata object overlays,
					if any, so that if the view appears again, the previously displayed
					metadata object overlays are removed.
				*/
				if !isSessionRunning {
					self.removeMetadataObjectOverlayLayers()
				}
				
				/*
					When the session starts running, the aspect ratio of the video preview may also change if a new session preset was applied.
					To keep the preview view's region of interest within the visible portion of the video preview, the preview view's region of
					interest will need to be updated.
				*/
				if isSessionRunning {
					self.previewView.setRegionOfInterestWithProposedRegionOfInterest(self.previewView.regionOfInterest)
				}
			}
		}
		keyValueObservations.append(keyValueObservation)
		
		/*
			Observe the previewView's regionOfInterest to update the AVCaptureMetadataOutput's
			rectOfInterest when the user finishes resizing the region of interest.
		*/
		keyValueObservation = previewView.observe(\.regionOfInterest, options: .new) { _, change in
			guard let regionOfInterest = change.newValue else { return }
			
			DispatchQueue.main.async {
				// Ensure we are not drawing old metadata object overlays.
				self.removeMetadataObjectOverlayLayers()
				
				// Translate the preview view's region of interest to the metadata output's coordinate system.
				let metadataOutputRectOfInterest = self.previewView.videoPreviewLayer.metadataOutputRectConverted(fromLayerRect: regionOfInterest)
				
				// Update the AVCaptureMetadataOutput with the new region of interest.
				self.sessionQueue.async {
					self.metadataOutput.rectOfInterest = metadataOutputRectOfInterest
				}
			}
		}
		keyValueObservations.append(keyValueObservation)
	
		let notificationCenter = NotificationCenter.default
		
		notificationCenter.addObserver(self, selector: #selector(sessionRuntimeError), name: .AVCaptureSessionRuntimeError, object: session)
		
		/*
			A session can only run when the app is full screen. It will be interrupted
			in a multi-app layout, introduced in iOS 9, see also the documentation of
			AVCaptureSessionInterruptionReason. Add observers to handle these session
			interruptions and show a preview is paused message. See the documentation
			of AVCaptureSessionWasInterruptedNotification for other interruption reasons.
		*/
		notificationCenter.addObserver(self, selector: #selector(sessionWasInterrupted), name: .AVCaptureSessionWasInterrupted, object: session)
		notificationCenter.addObserver(self, selector: #selector(sessionInterruptionEnded), name: .AVCaptureSessionInterruptionEnded, object: session)
	}
	
	private func removeObservers() {
		NotificationCenter.default.removeObserver(self, name: .AVCaptureSessionInterruptionEnded, object: session)
		NotificationCenter.default.removeObserver(self, name: .AVCaptureSessionWasInterrupted, object: session)
		NotificationCenter.default.removeObserver(self, name: .AVCaptureSessionRuntimeError, object: session)
		
		for keyValueObservation in keyValueObservations {
			keyValueObservation.invalidate()
		}
		keyValueObservations.removeAll()
	}
	
	@objc
	func sessionRuntimeError(notification: NSNotification) {
		guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else { return }
		
		print("Capture session runtime error: \(error)")
		
		/*
			Automatically try to restart the session running if media services were
			reset and the last start running succeeded. Otherwise, enable the user
			to try to resume the session running.
		*/
		if error.code == .mediaServicesWereReset {
			sessionQueue.async {
				if self.isSessionRunning {
					self.session.startRunning()
					self.isSessionRunning = self.session.isRunning
				}
			}
		}
 	}
	
	@objc
	func sessionWasInterrupted(notification: NSNotification) {
		/*
			In some scenarios we want to enable the user to resume the session running.
			For example, if music playback is initiated via control center while
			using AVCamBarcode, then the user can let AVCamBarcode resume
			the session running, which will stop music playback. Note that stopping
			music playback in control center will not automatically resume the session
			running. Also note that it is not always possible to resume, see `resumeInterruptedSession(_:)`.
		*/
		if let userInfoValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as AnyObject?,
			let reasonIntegerValue = userInfoValue.integerValue,
			let reason = AVCaptureSession.InterruptionReason(rawValue: reasonIntegerValue) {
			print("Capture session was interrupted with reason \(reason)")
			
			if reason == .videoDeviceNotAvailableWithMultipleForegroundApps {
				// Simply fade-in a label to inform the user that the camera is unavailable.
				self.cameraUnavailableLabel.isHidden = false
				self.cameraUnavailableLabel.alpha = 0
				UIView.animate(withDuration: 0.25) {
					self.cameraUnavailableLabel.alpha = 1
				}
			}
		}
	}
	
	@objc
	func sessionInterruptionEnded(notification: NSNotification) {
		print("Capture session interruption ended")
		
		if cameraUnavailableLabel.isHidden {
			UIView.animate(withDuration: 0.25,
				animations: {
					self.cameraUnavailableLabel.alpha = 0
				}, completion: { _ in
					self.cameraUnavailableLabel.isHidden = true
				}
			)
		}
	}
	
	// MARK: Drawing Metadata Object Overlay Layers
	
	private class MetadataObjectLayer: CAShapeLayer {
		var metadataObject: AVMetadataObject?
	}
	
	/**
		A dispatch semaphore is used for drawing metadata object overlays so that
		only one group of metadata object overlays is drawn at a time.
	*/
	private let metadataObjectsOverlayLayersDrawingSemaphore = DispatchSemaphore(value: 1)
	
	private var metadataObjectOverlayLayers = [MetadataObjectLayer]()
	
	private func createMetadataObjectOverlayWithMetadataObject(_ metadataObject: AVMetadataObject) -> MetadataObjectLayer {
		// Transform the metadata object so the bounds are updated to reflect those of the video preview layer.
		let transformedMetadataObject = previewView.videoPreviewLayer.transformedMetadataObject(for: metadataObject)
		
		// Create the initial metadata object overlay layer that can be used for either machine readable codes or faces.
		let metadataObjectOverlayLayer = MetadataObjectLayer()
		metadataObjectOverlayLayer.metadataObject = transformedMetadataObject
		metadataObjectOverlayLayer.lineJoin = kCALineJoinRound
		metadataObjectOverlayLayer.lineWidth = 7.0
		metadataObjectOverlayLayer.strokeColor = view.tintColor.withAlphaComponent(0.7).cgColor
		metadataObjectOverlayLayer.fillColor = view.tintColor.withAlphaComponent(0.3).cgColor
		
		if let faceMetadataObject = transformedMetadataObject as? AVMetadataFaceObject {
			metadataObjectOverlayLayer.path = CGPath(rect: faceMetadataObject.bounds, transform: nil)
		}
		
		return metadataObjectOverlayLayer
	}
	
	private var removeMetadataObjectOverlayLayersTimer: Timer?
	
	@objc
	private func removeMetadataObjectOverlayLayers() {
		for sublayer in metadataObjectOverlayLayers {
			sublayer.removeFromSuperlayer()
		}
		metadataObjectOverlayLayers = []
		
		removeMetadataObjectOverlayLayersTimer?.invalidate()
		removeMetadataObjectOverlayLayersTimer = nil
	}
    
    var countingFaces = 0
    var currentCount = 0
    var lastTime = 0.0
    var currentName = ""
	
	private func addMetadataObjectOverlayLayersToVideoPreviewView(_ metadataObjectOverlayLayers: [MetadataObjectLayer]) {
		// Add the metadata object overlays as sublayers of the video preview layer. We disable actions to allow for fast drawing.
        countingFaces = 0
        
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		for metadataObjectOverlayLayer in metadataObjectOverlayLayers {
			previewView.videoPreviewLayer.addSublayer(metadataObjectOverlayLayer)
            countingFaces += 1
		}
		CATransaction.commit()
        
        if (countingFaces > currentCount &&
            (Date.timeIntervalSinceReferenceDate - lastTime) > 5)
        {
            currentCount = countingFaces
            capturePhoto()
            
            lastTime = Date.timeIntervalSinceReferenceDate
        }
        
        self.currentCount = self.countingFaces
		
		// Save the new metadata object overlays.
		self.metadataObjectOverlayLayers = metadataObjectOverlayLayers
		
		// Create a timer to destroy the metadata object overlays.
		removeMetadataObjectOverlayLayersTimer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(removeMetadataObjectOverlayLayers), userInfo: nil, repeats: false)
	}
	
	// MARK: AVCaptureMetadataOutputObjectsDelegate
	
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
		// wait() is used to drop new notifications if old ones are still processing, to avoid queueing up a bunch of stale data.
        if metadataObjectsOverlayLayersDrawingSemaphore.wait(timeout: .now()) == .success {
			DispatchQueue.main.async {
				self.removeMetadataObjectOverlayLayers()
				
				var metadataObjectOverlayLayers = [MetadataObjectLayer]()
				for metadataObject in metadataObjects {
					let metadataObjectOverlayLayer = self.createMetadataObjectOverlayWithMetadataObject(metadataObject)
					metadataObjectOverlayLayers.append(metadataObjectOverlayLayer)
				}
				
				self.addMetadataObjectOverlayLayersToVideoPreviewView(metadataObjectOverlayLayers)
				
				self.metadataObjectsOverlayLayersDrawingSemaphore.signal()
			}
		}
	}
    
    // MARK: - AVCapturePhotoCaptureDelegate Methods
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        
        if let error = error {
            print("Error capturing photo: \(error)")
        } else {
            if let dataImage = photo.fileDataRepresentation() {
                
                if let img = UIImage(data: dataImage) {
                    let timeStamp :String = String(format:"%f.jpg", Date.timeIntervalSinceReferenceDate)
                    print(timeStamp)
                    
                    // Rotate image according to device orientation
                    var radians : Float = 0.0
                    switch UIDevice.current.orientation{
                    case .portrait:
                        radians = 0.0
                    case .portraitUpsideDown:
                        radians = Float.pi
                    case .landscapeLeft:
                        radians = -Float.pi/2
                    case .landscapeRight:
                        radians = Float.pi/2
                    default:
                        radians = 0.0
                    }
                    
                    let compressedImage = img.rotate(radians: radians)
                    
                    // If this was a manual trigger
                    // Then post to Google, checking for text
                    if (volumeChange)
                    {
                        print("Start OCR")
                        let r = STHTTPRequest(urlString: self.voiceToUrl)
                        r!.addData(toUpload: compressedImage, parameterName: "image", mimeType: "image/jpeg", fileName: timeStamp)
                        // r!.postDictionary = ["param1": "1", "param2": "2", "param3": "hello"]
                        r!.completionBlock = { (headers, body) in
                            // ...
                            var readString = body!
                            if body == "" && !self.killProcess
                            {
                                readString = self.errorResponse
                            }
                            self.audioResponse(withText: readString, andSpeed: 0.50)
                            print(readString)
                            self.volumeChange = false
                            self.killProcess = false
                        }
                        
                        r!.errorBlock = { (error) in
                            // ...
                            let nsError = error! as NSError
                            print(nsError.localizedDescription)
                            
                            let readString = "There was an error identifying anything"
                            self.audioResponse(withText: readString, andSpeed: 0.50)
                            self.volumeChange = false
                            self.killProcess = false
                        }
                        
                        r!.startAsynchronous()
                    }
                    else
                    {
                        // Otherwise go for facial recognition
                        print("Start Facial")
                        let r2 = STHTTPRequest(urlString: "http://111567b9.ngrok.io/upload")
                        r2!.addData(toUpload: compressedImage, parameterName: "image", mimeType: "image/jpeg", fileName: timeStamp)
                        
                        r2!.completionBlock = { (headers, body) in
                            if body != "" && !self.killProcess
                            {
                                let arr = body!.components(separatedBy: "%")
                                let readString = arr[1]
                                self.audioResponse(withText: readString, andSpeed: 0.5)
                                self.currentName = arr[0] //Store reference to last person received
                            }
                            print(body!)
                            print(Date.timeIntervalSinceReferenceDate)

                            self.volumeChange = false
                            self.killProcess = false
                        }
                        
                        r2!.errorBlock = { (error) in
                            let nsError = error! as NSError
                            print(nsError.localizedDescription)
                            self.volumeChange = false
                            self.killProcess = false
                        }
                        
                        r2!.startAsynchronous()
                    }
                }
            }
        }
    }
    
    // MARK: - Allow user to trigger image with volume button
    var volumeChange = false;
    
    // Create dummy volume
    let volumeView = MPVolumeView()
    
    // Create audioSession listening to outputVolume
    let audioSession = AVAudioSession()
    
    // Depending on the text, change the URL and error reponse
    var voiceToUrl = "http://111567b9.ngrok.io/ocr"
    var errorResponse = "I was unable to read the text..."
    
    @objc func listenVolumeButton() {
        volumeView.frame = CGRect(x: -20, y: -20, width: 0, height: 0);
        volumeView.volumeSlider.value = 0.9
        self.view.addSubview(volumeView)
        
        do {
            try audioSession.setActive(true)
            try audioSession.setCategory(AVAudioSessionCategoryPlayAndRecord, with: .defaultToSpeaker)
            try audioSession.setMode(AVAudioSessionModeSpokenAudio)
        } catch {
            print("Volume Button Error")
        }
        audioSession.addObserver(self, forKeyPath: "outputVolume", options: NSKeyValueObservingOptions.new, context: nil)
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "outputVolume" {
            if !volumeChange &&
                (Date.timeIntervalSinceReferenceDate - lastTime) > 5 &&
                speechRecognizer.status == .ready
            {
                //volumePressed()
                speechRecognizer.startRecording()
            }
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }

    func volumePressed(say text: String)
    {
        volumeChange = true
        capturePhoto()
        audioResponse(withText: text, andSpeed: 0.5)
        print("got in here")
        //Keep Volume at 0.9
        volumeView.volumeSlider.value = 0.9
    }
    
    // MARK: - Audio Response
    func audioResponse(withText text: String!, andSpeed speed: Float)
    {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US") //"en-GB"
        utterance.rate = speed
        
        let synthesizer = AVSpeechSynthesizer()
        synthesizer.speak(utterance)
    }
    
    // handle notification
    @objc func decipherVoice(_ notification: NSNotification) {
        
        if let response = notification.userInfo?["string"] as? String {
            if response.lowercased().range(of:"text") != nil || response.lowercased().range(of:"read") != nil {
                self.voiceToUrl = "http://111567b9.ngrok.io/ocr"
                self.errorResponse = "I was unable to read the text..."
                volumePressed(say: "Deciphering Text. One moment please.")
            } else if response.lowercased().range(of:"more") != nil || response.lowercased().range(of:"tell") != nil {
                print("Start More")
                let r2 = STHTTPRequest(urlString: "http://111567b9.ngrok.io/moreinfo")
                r2!.postDictionary = ["name": self.currentName];
                r2!.completionBlock = { (headers, body) in
                    if body != ""
                    {
                        let readString = self.currentName + body!
                        self.audioResponse(withText: readString, andSpeed: 0.5)
                    }
                    print(body!)
                    print(Date.timeIntervalSinceReferenceDate)
                }
                
                r2!.errorBlock = { (error) in
                    let nsError = error! as NSError
                    print(nsError.localizedDescription)
                }
                
                r2!.startAsynchronous()
                
            } else if response.lowercased().range(of:"what") != nil || response.lowercased().range(of:"thing") != nil {
                self.voiceToUrl = "http://111567b9.ngrok.io/label"
                self.errorResponse = "I was unable to identify the object..."
                volumePressed(say: "Identifying objects around you. One moment please.")
            }
        }
    }
}

// MARK: - Extensions
extension AVCaptureVideoOrientation {
	init?(deviceOrientation: UIDeviceOrientation) {
		switch deviceOrientation {
			case .portrait: self = .portrait
			case .portraitUpsideDown: self = .portraitUpsideDown
			case .landscapeLeft: self = .landscapeRight
			case .landscapeRight: self = .landscapeLeft
			default: return nil
		}
	}
	
	init?(interfaceOrientation: UIInterfaceOrientation) {
		switch interfaceOrientation {
			case .portrait: self = .portrait
			case .portraitUpsideDown: self = .portraitUpsideDown
			case .landscapeLeft: self = .landscapeLeft
			case .landscapeRight: self = .landscapeRight
			default: return nil
		}
	}
}

extension MPVolumeView {
    var volumeSlider:UISlider { // hacking for changing volume by programing
        var slider = UISlider()
        for subview in self.subviews {
            if subview is UISlider {
                slider = subview as! UISlider
                slider.isContinuous = false
                (subview as! UISlider).value = AVAudioSession.sharedInstance().outputVolume
                return slider
            }
        }
        return slider
    }
}

extension UIImage {
    func rotate(radians: Float) -> Data {
        var newSize = CGRect(origin: CGPoint.zero, size: self.size).applying(CGAffineTransform(rotationAngle: CGFloat(radians))).size
        //Trim off the extremely small float value to prevent core graphics from rounding it up
        newSize.width = floor(newSize.width)
        newSize.height = floor(newSize.height)
        
        UIGraphicsBeginImageContext(newSize);
        let context = UIGraphicsGetCurrentContext()!
        
        //Move origin to middle
        context.translateBy(x: newSize.width/2, y: newSize.height/2)
        //Rotate around middle
        context.rotate(by: CGFloat(radians))
        
        self.draw(in: CGRect(x: -self.size.width/2, y: -self.size.height/2, width: self.size.width, height: self.size.height))
        
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return UIImageJPEGRepresentation(newImage!, 0.25)!
    }
}




