# Notes from jwardell

## Architecture:

Uses a "MVCNC" architecture: Model-View-Controller-Networking-Coordinator
This is like MVC with 2 major distinctions:

1. Coordinators run the high level logic: deciding which windows are shown when, handling app-level logic, and integrating the Networking and Controller Layers.  They're the only thing that happend in the AppDelegate
2. A Networking layer is separate from the app logic and controller layer.  It is owned by the coordinator layer, and controllers can have a reference to it and interact with it (both getting updates and making changes)

## Third Party Code

There are 3 places I use other peoples' code:

__CocoaAsyncSocket__ for the lowest-level UDP support, marked public domain in the source , but no license info is available at the repo (https://github.com/robbiehanson/CocoaAsyncSocket) - this is managed via Carthage and is referenced in the Cartfile

__WeeblyTry__ to deal with one intermittent objective-c style throw from the KVO system when video loading fails early on, with apparently its own nonstandard license that appears very lenient ( https://github.com/Weebly/Try) - this is included in the "Third Party group" as source"

Code for video loading using AVPlayer started out as a copy-paste from a gist by charles boyd (https://gist.github.com/charlesboyd/e0e840e8af9e52836d51). It's basically been rewritten aside from some of the error reporting, and his gist lists itself as being licensed under "the Unlicense". I attribute the gist in PlayerViewController.swift.
