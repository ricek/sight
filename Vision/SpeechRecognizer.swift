//
//  SpeechRecognizer.swift
//  Vision
//
//  Created by Zak Wegweiser on 12/2/17.
//  Copyright © 2017 Apple. All rights reserved.
//

import Foundation
import UIKit
import Speech

enum SpeechStatus {
    case ready
    case recognizing
    case unavailable
}

class SpeechRecognizer: NSObject {
    
    var status = SpeechStatus.ready
    
    let audioEngine = AVAudioEngine()
    let speechRecognizer: SFSpeechRecognizer? = SFSpeechRecognizer()
    let request = SFSpeechAudioBufferRecognitionRequest()
    var recognitionTask: SFSpeechRecognitionTask?
    
    func initialize()
    {
        switch (SFSpeechRecognizer.authorizationStatus()) {
            case .notDetermined:
                askSpeechPermission()
            case .authorized:
                self.status = .ready
            case .denied, .restricted:
                self.status = .unavailable
        }
    }
    
    /// Ask permission to the user to access their speech data.
    func askSpeechPermission() {
        SFSpeechRecognizer.requestAuthorization { status in
            OperationQueue.main.addOperation {
                switch status {
                case .authorized:
                    self.status = .ready
                default:
                    self.status = .unavailable
                }
            }
        }
    }
    
    /// Start streaming the microphone data to the speech recognizer to recognize it live.
    func startRecording() {
        // Setup audio engine and speech recognizer
        let node = audioEngine.inputNode
        let recordingFormat = node.outputFormat(forBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.request.append(buffer)
        }
        
        // Prepare and start recording
        audioEngine.prepare()
        do {
            try audioEngine.start()
            self.status = .recognizing
        } catch {
            return print(error)
        }
        
        // Used to detect current speech
        var currentRet = ""
        // Analyze the speech
        recognitionTask = speechRecognizer?.recognitionTask(with: request, resultHandler: { result, error in
            if let result = result {
                let ret = result.bestTranscription.formattedString
                currentRet = ret
                
                if (ret != "") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: {
                        if (result.bestTranscription.formattedString == currentRet)
                        {
                            print(result.bestTranscription.formattedString)
                            self.cancelRecording()
                            currentRet = ""
                            
                            let dataDict:[String: String] = ["string": (result.bestTranscription.formattedString)]
                            
                            // post a notification
                            NotificationCenter.default.post(name: NSNotification.Name(rawValue: "DoneListening"), object: nil, userInfo: dataDict)
                        }
                    })
                }
            } else if let error = error {
                print(error)
            }
        })
    }
    
    /// Stops and cancels the speech recognition.
    func cancelRecording() {
        audioEngine.stop()
        let node = audioEngine.inputNode
        node.removeTap(onBus: 0)
        recognitionTask?.cancel()
    }
    
    @IBAction func microphonePressed() {
        switch status {
        case .ready:
            startRecording()
            status = .recognizing
        case .recognizing:
            cancelRecording()
            status = .ready
        default:
            break
        }
    }
}


