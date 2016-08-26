//
//  PreferencesViewController.swift
//  UDPServerTest
//
//  Created by Joseph Wardell on 8/22/16.
//  Copyright © 2016 Joseph Wardell. All rights reserved.
//

import Cocoa

final class PreferencesViewController: MessageHandlerViewController {

    @IBOutlet weak var portField: NSTextField!
    @IBOutlet weak var startStopButton: NSButton!

    private var preferredServerPort : UInt16 {
        
        return UInt16(portField.intValue)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        startStopButton.target = self
        startStopButton.action = #selector(startStopButtonPressed(_:))

        class RestrictiveNumberFormatter : NSNumberFormatter {
            override func isPartialStringValid(partialString: String, newEditingString newString: AutoreleasingUnsafeMutablePointer<NSString?>, errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>) -> Bool {
                guard !partialString.isEmpty else { return true }
                
                guard let out = Int(partialString) else { return false }
                
                return out <= Int(PortNumber.max)
            }
        }
        portField.formatter = RestrictiveNumberFormatter()
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
        updateUI()
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(messageHandlerDidStart(_:)),
                                                         name: MessageHandler.Notifications.DidStartListening,
                                                         object: messageHandler)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(messageHandlerDidStop(_:)),
                                                         name: MessageHandler.Notifications.DidStopListening,
                                                         object: messageHandler)
    }
    
    override func viewWillDisappear() {
        super.viewWillDisappear()
        
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }

    // MARK:- Updating UI
    
    func updateUI() {

        guard let server = messageHandler?.server else { return }

        let port = server.running ? (server.port ?? 0) : NSUserDefaults.standardUserDefaults().preferredServerPort

        portField.stringValue = "\(port)"
        portField.enabled = !server.running
        portField.becomeFirstResponder()

        startStopButton.intValue = server.running ? 1 : 0
    }

    // MARK:- Actions

    func startStopButtonPressed(sender:NSButton) {
        
        NSUserDefaults.standardUserDefaults().preferredServerPort = preferredServerPort
        
        messageHandler?.toggleServerOnPort(preferredServerPort)
        
        NSUserDefaults.standardUserDefaults().startServerOnStartup = sender.integerValue != 0
    }
    
    // MARK:- Notifications

    func messageHandlerDidStart(notification:NSNotification) {
        updateUI()
    }
    func messageHandlerDidStop(notification:NSNotification) {
        updateUI()
    }

}
