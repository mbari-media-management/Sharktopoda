//
//  VideoPlayerCoordinator.swift
//  Sharktopoda
//
//  Created by Joseph Wardell on 8/23/16.
//

import Cocoa

/*
 Coordinates video playback through a group of window controllers.
 Basically, handles the video playback aspect of the app
 And handles responding to commands from the Networking layer
 */
final class VideoPlayerCoordinator: NSResponder, VideoPlaybackCoordinator{
    
    
    struct StoryboardIdentifiers {
        static let OpenURLWindowController = "OpenURLWindowController"
        static let VideoPlayerWindowController = "VideoPlayerWindowController"
        static let TestingPanelWindowController = "TestingPanelWindowController"
    }
    
    var storyboard : NSStoryboard!
    
    lazy var openURLPromptWindowController : NSWindowController = {
        return self.storyboard.instantiateControllerWithIdentifier(StoryboardIdentifiers.OpenURLWindowController) as! NSWindowController
    }()
    
    // matches player controllers to their UUID
    // this allows us to access videos by UUID
    // and maintain the lifetime of the players
    var videoPlayerWindowControllers = [NSUUID:PlayerWindowController]()
    
    // the frontmost video player window controller, for when a client asks for info about the frontmost video
    var frontmostPlayerWindowController : PlayerWindowController?
    
    // a dictionary matching UUIDs to callbacks, for when we're told to capture frames
    typealias frameCaptureCallback = (success:Bool, error:NSError?, requestedTimeInMilliseconds:UInt?, actualTimeInMilliseconds:UInt?)->()
    var frameCaptureCallbacks = [NSUUID:(frameCaptureCallback)]()

    
    // MARK:- Actions
    
    // shows the openURL window
    @IBAction func openURL(sender:AnyObject) {
        
        openURLPromptWindowController.window?.center()
        openURLPromptWindowController.showWindow(self)
    }
    
    // sent by a client class,
    // ask client for an URL to play back, then validate it and show a video player window
    @IBAction func openURLForPlayback(sender:AnyObject) {
        
        guard let requester = sender as? VideoURLPlaybackRequester else { return }
        let possibleURL = requester.urlToPlay
        
        if let url = NSURL(string:possibleURL) {
            self.openVideoAtURL(url, usingUUID:NSUUID()) { (success, error) in
                
                if !success {
                    dispatch_async(dispatch_get_main_queue()) {
                        
                        let alert = NSAlert()
                        alert.messageText = "Failed to Load Video"
                        alert.informativeText = "Could not load video at \(url.description ?? "unknown")\n\nerror:\(error!.localizedDescription ?? "unknown")"
                        alert.runModal()
                    }
                }
            }
        }
        // otherwise, do nothing...
    }
    
    // shows an NSOpenPanel and lets the user choose one video file to play
    @IBAction func openDocument(sender:AnyObject) {
        
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canCreateDirectories = false
        openPanel.canChooseFiles = true
        openPanel.allowedFileTypes = ["public.audiovisual-content"]
        
        openPanel.beginWithCompletionHandler { (result) -> Void in
            if result == NSFileHandlingPanelOKButton {
                if let url = openPanel.URL {
                    
                    self.openVideoAtURL(url, usingUUID:NSUUID()) { (success, error) in
                        
                        if !success {
                            dispatch_async(dispatch_get_main_queue()) {
                                
                                let alert = NSAlert()
                                alert.messageText = "Failed to Load Video"
                                alert.informativeText = "Could not load video at \(url.description ?? "unknown")\n\nerror:\(error!.localizedDescription ?? "unknown")"
                                alert.runModal()
                            }

                        }
                    }
                }
            }
        }
    }
    
    #if false
    // these methods are for testing purposes.
    // Check out the AVPlayerTest project to see them in use
    lazy var testWindowController : TestWindowController = {
        
        var out = self.storyboard.instantiateControllerWithIdentifier(StoryboardIdentifiers.TestingPanelWindowController) as! TestWindowController
        out.testViewController.coordinator = self
        return out
    }()
    
    @IBAction func showTestWindow(sender:AnyObject) {
        
        testWindowController.showWindow(self)
    }
    #endif
    
    // MARK:- URL Validation
    
    enum URLValidation {
        case url(NSURL)
        case error(NSError)
    }
    
    func validateURLSchemeForURL(url:NSURL) -> URLValidation {
        
        // only accept http and file urls
        guard ["file", "http", "https"].contains(url.scheme!) else {
            return .error(errorWithCode(.unsupportedURL, description:"The url \(url) is not supported"))
        }
        return .url(url)
    }
    
    func validateURL(url:NSURL) -> URLValidation {
        
        // only accept http and file urls
        
        // first, validate the scheme
        let validURL = validateURLSchemeForURL(url)
        switch validURL {
        case .error:
            return validURL
            
        case .url:
            // if it's a file url, make sure it represents a reachable resource
            if "file" == url.scheme {
                var error : NSError?
                if !url.checkResourceIsReachableAndReturnError(&error) {
                    return .error(error!)
                }
            }
            
            return .url(url)
        }
    }
    
    
    // MARK:- Introspection of videos
    
    func playerWindowControllerForUUID(uuid:NSUUID) throws -> PlayerWindowController {
        guard let out = videoPlayerWindowControllers[uuid] else {
            throw(errorWithCode(.noVideoForThisUUID, description: "No video is available with UUID \(uuid.UUIDString)"))
        }
        
        return out
    }
    
    func infoForVideoWithUUID(uuid:NSUUID) throws -> (url:NSURL, uuid:NSUUID) {
        let pwc = try playerWindowControllerForUUID(uuid)
        
        guard let url = pwc.videoURL else {
            throw(errorWithCode(.noURLForThisUUID, description: "No url associated with video with UUID \(uuid.UUIDString)"))
        }
        guard uuid == pwc.uuid else {
            throw(errorWithCode(.bizarreInconsistency, description: "Bizarre inconsistency at \(#file):\(#line)"))
        }
        
        return (url, uuid)
    }
    
    // MARK:- Utility
    
    func errorWithCode(code:ErrorCode, description:String) -> NSError {
        return NSError(domain: "VideoPlayerCoordinator", code: code.rawValue,
                       userInfo: [NSLocalizedDescriptionKey:description])
    }
    
}


// MARK:- SharkVideoCoordination

extension VideoPlayerCoordinator : SharkVideoCoordination {
    
    // MARK:- SharkVideoCoordination:Video Playback
    
    // the main function that validates and then shows a video given an URL
    // this is the method that is called no matter how a video url is chosen (via open dialog, via openURL window, or via network)
    func openVideoAtURL(url:NSURL, usingUUID uuid:NSUUID, callback:(success:Bool, error:NSError?) -> ()) {
        
        switch validateURL(url) {
        case .error(let error):
            callback(success: false, error: error)
            return
        default:
            break
        }
        
        let playerWC = self.storyboard.instantiateControllerWithIdentifier("VideoPlayerWindowController") as! PlayerWindowController
        playerWC.uuid = uuid
        playerWC.videoURL = url
        playerWC.delegate = self
        
        let playerVC = playerWC.playerViewController
        playerVC.videoLoadCompletionCallback = callback
        playerVC.frameGrabbingCallback = receivedFrameGrabbingOutcome
        
        playerWC.showVideo()
        
        videoPlayerWindowControllers[uuid] = playerWC
    }
    
    
    
    // MARK:- SharkVideoCoordination:Video Info
    
    
    func returnInfoForVideoWithUUID(uuid:NSUUID) throws -> [String:AnyObject] {
        
        let info = try infoForVideoWithUUID(uuid)
        return ["url":info.url, "uuid":info.uuid]
    }
    
    func returnInfoForFrontmostVideo() throws -> [String : AnyObject] {
        
        guard let frontpwc = frontmostPlayerWindowController else {
            throw(errorWithCode(.focusedVideoWindowDoesNotExist, description: "There is no focused video window"))
        }
        
        guard let uuid = frontpwc.uuid else {
            throw(errorWithCode(.bizarreInconsistency, description: "Bizarre inconsistency at \(#file):\(#line)"))
        }
        
        return try returnInfoForVideoWithUUID(uuid)
    }
    
    func returnAllVideoInfo() throws -> [[String:AnyObject]] {
        
        var out = [[String:AnyObject]]()
        
        for (thisUUID, _) in videoPlayerWindowControllers {
            let (thisURL, _) = try infoForVideoWithUUID(thisUUID)
            out.append(["url":thisURL.description, "uuid":thisUUID.UUIDString])
        }
        return out
    }
    
    func requestPlaybackStatusForVideoWithUUID(uuid inUUID:NSUUID) throws -> SharkVideoPlaybackStatus {
        
        let pwc = try playerWindowControllerForUUID(inUUID)
        
        switch pwc.playerViewController.videoPlaybackRate {
        case 1.0:
            return .playing
        case let (x) where x < 0:
            return .shuttlingInReverse
        case let x where x > 0:
            return .shuttlingForward
        default:
            return .paused
        }
    }
    
    func requestElapsedTimeForVideoWithUUID(uuid inUUID:NSUUID) throws -> UInt  {
        let pwc = try playerWindowControllerForUUID(inUUID)
        
        return pwc.playerViewController.videoElpasedTimeInMilliseconds
    }

    func advanceToTimeInMilliseconds(time: UInt, forVideoWithUUID inUUID: NSUUID) throws {
        let pwc = try playerWindowControllerForUUID(inUUID)
        
        try pwc.playerViewController.advanceToTimeInMilliseconds(time)
    }
    
    func captureCurrentFrameForVideWithUUID(uuid inUUID:NSUUID, andSaveTo saveLocation:NSURL, referenceUUID:NSUUID,
                                                 then callback:(success:Bool, error:NSError?, requestedTimeInMilliseconds:UInt?, actualTimeInMilliseconds:UInt?)->()) throws {
        let pwc = try playerWindowControllerForUUID(inUUID)

        switch validateURLSchemeForURL(saveLocation) {
        case .error(let error):
            callback(success: false, error: error, requestedTimeInMilliseconds:nil, actualTimeInMilliseconds:nil)
            return
        default:
            break
        }

        frameCaptureCallbacks[referenceUUID] = callback
        pwc.playerViewController.grabFrameAndSaveItTo(saveLocation, destinationUUID: referenceUUID)
    }
    
    func receivedFrameGrabbingOutcome(outcome:PlayerViewController.FrameGrabbingOutcome) {
        
        dispatch_async(dispatch_get_main_queue()) {
            
            switch outcome {
            case .failure (let error, let requestedTime, let destinationUUID):
                if let callback = self.frameCaptureCallbacks.removeValueForKey(destinationUUID) {
                    callback(success: false, error: error, requestedTimeInMilliseconds:requestedTime, actualTimeInMilliseconds:nil)
                }
                
                
            case .success(let requestedTime, let destinationUUID, let actualTime):
                if let callback = self.frameCaptureCallbacks.removeValueForKey(destinationUUID) {
                    callback(success:true, error:nil, requestedTimeInMilliseconds:requestedTime, actualTimeInMilliseconds:actualTime)
                }
                break
            }
        }
    }

    // MARK:- SharkVideoCoordination:Control
    
    func focusWindowForVideoWithUUID(uuid inUUID:NSUUID) throws {
        let pwc = try playerWindowControllerForUUID(inUUID)
        
        pwc.window?.makeKeyAndOrderFront(self)
    }
    
    func closeWindowForVideoWithUUID(uuid inUUID:NSUUID) throws {
        let pwc = try playerWindowControllerForUUID(inUUID)

        pwc.close()
    }

    
    func playVideoWithUUID(uuid inUUID:NSUUID, rate:Double) throws {
        let pwc = try playerWindowControllerForUUID(inUUID)
        
        pwc.playerViewController.playVideoAtRate(rate)
    }
    
    ////    Pauses the playback for the video specified by the UUID
    func pauseVideoWithUUID(uuid inUUID:NSUUID) throws {
        let pwc = try playerWindowControllerForUUID(inUUID)
        
        pwc.playerViewController.pauseVideo(self)
    }
    
    
    func advanceToNextFrameInVideoWithUUID(uuid inUUID:NSUUID, byFrameCount:Int) throws {
        let pwc = try playerWindowControllerForUUID(inUUID)

        try pwc.playerViewController.advanceByFrameNumber(1)
    }

    enum ErrorCode : Int {
        case unsupportedURL = 11
        case noVideoForThisUUID = 12
        case noURLForThisUUID = 13
        case focusedVideoWindowDoesNotExist = 14
        case bizarreInconsistency = 99
    }
}

// MARK:-

extension VideoPlayerCoordinator : PlayerWindowControllerDelegate {
    
    func playerWindowWillClose(notification: NSNotification) {
        let window = notification.object as! NSWindow
        let playerWC = window.windowController as! PlayerWindowController
        
        // don't manage the player anymore
        // also, release it so that playback will end...
        videoPlayerWindowControllers.removeValueForKey(playerWC.uuid!)
    }
    
    func playerWindowDidAppear(notification: NSNotification) {
        let window = notification.object as! NSWindow
        let playerWC = window.windowController as! PlayerWindowController

        frontmostPlayerWindowController = playerWC
    }
    
    func playerWindowDidBecomeMain(notification: NSNotification) {
        let window = notification.object as! NSWindow
        let playerWC = window.windowController as! PlayerWindowController
        
        frontmostPlayerWindowController = playerWC
    }
}
