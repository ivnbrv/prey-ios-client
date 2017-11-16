//
//  ReportPhoto.swift
//  Prey
//
//  Created by Javier Cala Uribe on 26/05/16.
//  Copyright © 2016 Fork Ltd. All rights reserved.
//

import Foundation
import AVFoundation
import UIKit

protocol PhotoServiceDelegate {
    func photoReceived(_ photos:NSMutableDictionary)
}


// Context
var CapturingStillImageContext = "CapturingStillImageContext"


class ReportPhoto: NSObject {
 
    // MARK: Properties
    
    // Check device authorization
    var isDeviceAuthorized : Bool {
        let authStatus:AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: AVMediaType.video)
        return (authStatus == AVAuthorizationStatus.authorized) ? true : false
    }
    
    // Check camera number
    var isTwoCameraAvailable : Bool {
        let videoDevices = AVCaptureDevice.devices(for: AVMediaType.video)
        return (videoDevices.count > 1) ? true : false
    }
    
    // Check observer stillImageOutput.capturingStillImage
    var isObserveImageOutput = false
    
    // Photo array
    var photoArray    = NSMutableDictionary()
    
    var waitForRequest = false
    
    // ReportPhoto Delegate
    var delegate: PhotoServiceDelegate?
    
    // Session Device
    let sessionDevice:AVCaptureSession
    
    // Session Queue
    let sessionQueue:DispatchQueue
    
    // Device Input
    var videoDeviceInput:AVCaptureDeviceInput?
    
    // Image Output
    let stillImageOutput = AVCaptureStillImageOutput()
    
    
    // MARK: Init
    
    // Init camera session
    override init() {
        
        // Create AVCaptureSession
        sessionDevice = AVCaptureSession()
        
        // Set session to PresetLow
        if sessionDevice.canSetSessionPreset(AVCaptureSession.Preset.low) {
            sessionDevice.sessionPreset = AVCaptureSession.Preset.low
        }

        // In general it is not safe to mutate an AVCaptureSession or any of its inputs, outputs, 
        // or connections from multiple threads at the same time.
        // Why not do all of this on the main queue?
        // AVCaptureSession.startRunning() is a blocking call which can take a long time. We dispatch session setup 
        // to the sessionQueue so that the main queue isn't blocked (which keeps the UI responsive).
        sessionQueue = DispatchQueue(label: "session queue", attributes: [])
    }
    
    // Start Session
    func startSession() {
        
        sessionQueue.async {
            
            // Check error with device
            guard let videoDevice = ReportPhoto.deviceWithPosition(AVCaptureDevice.Position.back) else {
                PreyLogger("Error with AVCaptureDevice")
                self.delegate?.photoReceived(self.photoArray)
                return
            }
            
            // Set AVCaptureDeviceInput
            do {
                self.videoDeviceInput = try AVCaptureDeviceInput(device:videoDevice)
                
                // Add session input
                guard self.sessionDevice.canAddInput(self.videoDeviceInput!) else {
                    PreyLogger("Error add session input")
                    self.delegate?.photoReceived(self.photoArray)
                    return
                }
                self.sessionDevice.addInput(self.videoDeviceInput!)
                
                // Add session output
                guard self.sessionDevice.canAddOutput(self.stillImageOutput) else {
                    PreyLogger("Error add session output")
                    self.delegate?.photoReceived(self.photoArray)
                    return
                }
                self.stillImageOutput.outputSettings = [AVVideoCodecKey: AVVideoCodecJPEG]
                self.sessionDevice.addOutput(self.stillImageOutput)
                
                // Start session
                self.sessionDevice.startRunning()
                
                // KeyObserver
                self.addObserver(self, forKeyPath:"stillImageOutput.capturingStillImage", options: ([.old,.new]), context: &CapturingStillImageContext)
                self.isObserveImageOutput = true
                
                // Delay 
                let timeValue = DispatchTime.now() + Double(Int64(1 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
                self.sessionQueue.asyncAfter(deadline: timeValue, execute: { () -> Void in
                    
                    // Set flash off
                    if let deviceInput = self.videoDeviceInput {
                        self.setFlashModeOff(deviceInput.device)
                    }
                    
                    // Capture a still image
                    if let videoConnection = self.stillImageOutput.connection(with: AVMediaType.video) {
                        guard videoConnection.isEnabled else {
                            // Error: return to delegate
                            self.delegate?.photoReceived(self.photoArray)
                            return
                        }
                        // Check current state
                        guard self.stillImageOutput.isCapturingStillImage == false else {
                            // Error: return to delegate
                            self.delegate?.photoReceived(self.photoArray)
                            return
                        }
                        // Capture image
                        self.stillImageOutput.captureStillImageAsynchronously(from: videoConnection, completionHandler:self.checkPhotoCapture(true))
                    } else {
                        // Error: return to delegate
                        self.delegate?.photoReceived(self.photoArray)
                    }
                })
                
            } catch let error {
                PreyLogger("AVCaptureDeviceInput error: \(error.localizedDescription)")
                self.delegate?.photoReceived(self.photoArray)
            }
        }
    }
    
    // Stop Session
    func stopSession() {
        sessionQueue.async {
            
            // Remove current device input
            self.sessionDevice.beginConfiguration()
            
            // Remove session input
            if !self.sessionDevice.canAddInput(self.videoDeviceInput!) {
                self.sessionDevice.removeInput(self.videoDeviceInput!)
            }
            
            // Remove session output
            if !self.sessionDevice.canAddOutput(self.stillImageOutput) {
                self.sessionDevice.removeOutput(self.stillImageOutput)
            }
            
            // Set session to PresetLow
            if self.sessionDevice.canSetSessionPreset(AVCaptureSession.Preset.low) {
                self.sessionDevice.sessionPreset = AVCaptureSession.Preset.low
            }
            
            // End session config
            self.sessionDevice.commitConfiguration()
            
            // Stop session
            self.sessionDevice.stopRunning()
        }
    }
    
    // MARK: Functions

    // Remove observer
    func removeObserverForImage() {
        // Remove key oberver
        if self.isObserveImageOutput {
            self.removeObserver(self, forKeyPath:"stillImageOutput.capturingStillImage", context:&CapturingStillImageContext)
            self.isObserveImageOutput = false
        }
    }
    
    // Completion Handler to Photo Capture
    func checkPhotoCapture(_ isFirstPhoto:Bool) -> (CMSampleBuffer?, Error?) -> Void {
        
        let actionPhotoCapture: (CMSampleBuffer?, Error?) -> Void = { (sampleBuffer, error) in
            
            guard error == nil else {
                PreyLogger("Error CMSampleBuffer")
                self.delegate?.photoReceived(self.photoArray)
                return
            }
            
            // Change SampleBuffer to NSData
            guard let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(sampleBuffer!) else {
                PreyLogger("Error CMSampleBuffer to NSData")
                self.delegate?.photoReceived(self.photoArray)
                return
            }
            
            // Save image to Photo Array
            guard let image = UIImage(data: imageData) else {
                PreyLogger("Error NSData to UIImage")
                self.delegate?.photoReceived(self.photoArray)
                return
            }
            
            if isFirstPhoto {
                self.photoArray.removeAllObjects()
                self.photoArray.setObject(image, forKey: "picture" as NSCopying)
            } else {
                self.photoArray.setObject(image, forKey: "screenshot" as NSCopying)
            }
            
            // Check if two camera available
            if self.isTwoCameraAvailable && isFirstPhoto {
                self.sessionQueue.async {
                    self.getSecondPhoto()
                }
            } else {
                // Send Photo Array to Delegate
                self.delegate?.photoReceived(self.photoArray)
            }
        }
     
        return actionPhotoCapture
    }

    // Get second photo
    func getSecondPhoto() {
        
        // Set captureDevice
        guard let videoDevice = ReportPhoto.deviceWithPosition(AVCaptureDevice.Position.front) else {
            PreyLogger("Error with AVCaptureDevice")
            self.delegate?.photoReceived(self.photoArray)
            return
        }
        
        // Set AVCaptureDeviceInput
        do {
            let frontDeviceInput = try AVCaptureDeviceInput(device:videoDevice)
            
            // Remove current device input
            self.sessionDevice.beginConfiguration()
            self.sessionDevice.removeInput(self.videoDeviceInput!)
            
            // Add session input
            guard self.sessionDevice.canAddInput(frontDeviceInput) else {
                PreyLogger("Error add session input")
                self.delegate?.photoReceived(self.photoArray)
                return
            }
            self.sessionDevice.addInput(frontDeviceInput)
            self.videoDeviceInput = frontDeviceInput
            
            // Set session to PresetLow
            if self.sessionDevice.canSetSessionPreset(AVCaptureSession.Preset.low) {
                self.sessionDevice.sessionPreset = AVCaptureSession.Preset.low
            }
            
            // End session config
            self.sessionDevice.commitConfiguration()
            
            
            // Delay
            let timeValue = DispatchTime.now() + Double(Int64(1 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
            self.sessionQueue.asyncAfter(deadline: timeValue, execute: { () -> Void in
                
                // Set flash off
                if let deviceInput = self.videoDeviceInput {
                    self.setFlashModeOff(deviceInput.device)
                }
                
                // Capture a still image
                if let videoConnection = self.stillImageOutput.connection(with: AVMediaType.video) {
                    guard videoConnection.isEnabled else {
                        // Error: return to delegate
                        self.delegate?.photoReceived(self.photoArray)
                        return
                    }
                    // Check current state
                    guard self.stillImageOutput.isCapturingStillImage == false else {
                        // Error: return to delegate
                        self.delegate?.photoReceived(self.photoArray)
                        return
                    }
                    // Capture image
                    self.stillImageOutput.captureStillImageAsynchronously(from: videoConnection, completionHandler:self.checkPhotoCapture(false))
                } else {
                    // Error: return to delegate
                    self.delegate?.photoReceived(self.photoArray)
                }
            })
            
        } catch let error {
            PreyLogger("AVCaptureDeviceInput error: \(error.localizedDescription)")
            self.delegate?.photoReceived(self.photoArray)
        }
    }
    
    // Set shutter sound off
    func setShutterSoundOff() {
        var soundID:SystemSoundID = 0
        let pathFile = Bundle.main.path(forResource: "shutter", ofType: "aiff")
        let shutterFile = URL(fileURLWithPath: pathFile!)
        AudioServicesCreateSystemSoundID((shutterFile as CFURL), &soundID)
        AudioServicesPlaySystemSound(soundID)
    }
    
    // Set Flash Off
    func setFlashModeOff(_ device:AVCaptureDevice) {
        
        if (device.hasFlash && device.isFlashModeSupported(AVCaptureDevice.FlashMode.off)) {
            // Set AVCaptureFlashMode
            do {
                try device.lockForConfiguration()
                device.flashMode = AVCaptureDevice.FlashMode.off
                device.unlockForConfiguration()
                
            } catch let error {
                PreyLogger("AVCaptureFlashMode error: \(error.localizedDescription)")
            }
        }
    }
    
    // Observer Key
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if let changeValue = change?[.newKey] {
            if ( (context == &CapturingStillImageContext) && ((changeValue as AnyObject).boolValue == true) ) {
                // Set shutter sound off
                self.setShutterSoundOff()
            }
        }
    }
    
    // Return AVCaptureDevice
    class func deviceWithPosition(_ position:AVCaptureDevice.Position) -> AVCaptureDevice? {
        // Get devices array
        guard let devicesArray = AVCaptureDevice.devices(for: AVMediaType.video) as? [AVCaptureDevice] else {
            return nil
        }
        // Search for device
        for device in devicesArray {
            if device.position == position {
                return device
            }
        }
        return nil
    }
}
