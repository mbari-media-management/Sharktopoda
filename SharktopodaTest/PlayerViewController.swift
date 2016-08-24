//
//  PlayerViewController.swift
//  AVPlayerTest
//
//  Created by Joseph Wardell on 8/22/16.
//  Copyright © 2016 Joseph Wardell. All rights reserved.
//
// with many thanks to charlesboyd https://gist.github.com/charlesboyd/e0e840e8af9e52836d51

import Cocoa
import AVKit
import AVFoundation
import MediaAccessibility

class PlayerViewController: NSViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

    }
    
    var videoURL : NSURL? {
        get {
            return representedObject as? NSURL
        }
        set {
            representedObject = newValue
        }
    }
    
    override var representedObject: AnyObject? {
        didSet {
            view.window?.title = url?.lastPathComponent ?? "Movie"
        }
    }

    @IBOutlet weak var playerView: AVPlayerView! {
        didSet {
            playerView.controlsStyle = .Floating
            playerView.showsSharingServiceButton = true
        }
    }
    
    @IBOutlet weak var spinner: NSProgressIndicator?
    
    var url : NSURL? {
        return representedObject as? NSURL
    }
    

    override func viewWillAppear() {
        super.viewWillAppear()
        
        if nil == videoPlayer {
            openVideo()
        }
    }
    
    var videoPlayer:AVPlayer?
    
    // MARK:- KVO
    
    override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {
        /*  Called upon a status change for the video asset requested in `loadVideo(..)`. Add the following
         code to your class's `observeValueForKeyPath` function if you already have one.
         */
        
        //Verify the call is for the videoPlayer's status change
        if(object===videoPlayer?.currentItem && keyPath!=="status") {
            processVideoPlayerStatus()
        }
        else if (keyPath == "presentationSize") {
            updateWindowForMediaSize()
        }
    }

    
    // MARK:- Video Setup
    
    private func openVideo() {
        
        guard let url = url else { return }
        
        videoPlayer = AVPlayer(URL: url)
        playerView.player = videoPlayer
        
        videoPlayer?.allowsExternalPlayback = false

        // hide the player and start the spinner
        playerView.hidden = true
        spinner?.startAnimation(self)
        
        videoPlayer?.currentItem?.addObserver(self, forKeyPath: "status", options: NSKeyValueObservingOptions(), context: nil);
        videoPlayer?.currentItem?.addObserver(self, forKeyPath: "presentationSize", options: NSKeyValueObservingOptions(), context: nil);
    }
    
    func processVideoPlayerStatus() {
        
        //Verify we can read info about the asset currently loading
        if(videoPlayer?.currentItem == nil || videoPlayer?.currentItem?.status == nil){
            debugPrint("A video asset's status changed but the asset or its status returned nil. Status unknown.");
            videoLoadFailed();
            return;
        }
        
        //Get infromation about the asset for use below
        let videoStatus:AVPlayerItemStatus = (videoPlayer?.currentItem!.status)!;
        let assetString:String = (videoPlayer?.currentItem!.asset.description)!;
        
        //Take different actions based on the asset's new status
        if(videoStatus == AVPlayerItemStatus.ReadyToPlay){
            debugPrint("A video asset is ready to play. (Asset Description: \(assetString))");
            videoReady();
        }else if(videoStatus == AVPlayerItemStatus.Failed){
            let paybackError:NSError? = videoPlayer?.currentItem?.error;
            let asset = videoPlayer?.currentItem!.asset;
            print("A video asset failed to load.\n\tAsset Description: \(assetString)\n\tAsset Readable: \(asset?.readable)\n\tAsset Playable: \(asset?.playable)\n\tAsset Has Protected Content: \(asset?.hasProtectedContent)\n\tFull error output:\n\(paybackError)");
            videoLoadFailed();
        }else if(videoStatus == AVPlayerItemStatus.Unknown){
            //The asset should have started in an Unknown state, so it *should* not have changed into this state
            debugPrint("A video asset has an unknown status. (Asset Description: \(assetString))");
            videoLoadFailed();
        }
        
        //De-register for infomation about the item because it is now either ready or failed to load
        videoPlayer?.currentItem?.removeObserver(self, forKeyPath: "status");
    }
    

    func videoReady(){

        spinner?.stopAnimation(self)
        playerView.hidden = false
        
        // apparently, this must be set here, after the video is ready, or it will turn on anyway
        videoPlayer?.allowsExternalPlayback = false
    }
    
    func videoLoadFailed(){
        
        print("The video load failed! (See the console output)");
    }

    var videoPlaybackRate : Double {
        return Double(videoPlayer?.rate ?? 0)
    }
    
    // MARK:- Actions
    
    @IBAction func playVideo(sender:AnyObject) {
        
        playVideoAtRate()
    }
    
    @IBAction func pauseVideo(sender:AnyObject) {
        
        videoPlayer?.pause()
    }

    func playVideoAtRate(rate:Double = 1) {
        
        guard let videoPlayer = videoPlayer else { return } // TODO: should probably report this as a failure
        
        if videoPlayer.currentTime() >= videoPlayer.currentItem?.duration {
            let frameRate : Int32 = (videoPlayer.currentItem!.currentTime().timescale)
            videoPlayer.seekToTime(CMTimeMakeWithSeconds(0, frameRate))
        }
        
        if videoPlayer.rate == 0 {
            videoPlayer.play()
        }
        if rate != Double(videoPlayer.rate) {
            videoPlayer.setRate(Float(rate), time: kCMTimeInvalid, atHostTime: kCMTimeInvalid)
        }
    }


    
    // MARK:- UI Updating
    
    func updateWindowForMediaSize() {
        
        view.window?.setContentSize(playerView.player!.currentItem!.presentationSize)
        view.window?.center()
        
        videoPlayer?.currentItem?.removeObserver(self, forKeyPath: "presentationSize");
    }

}