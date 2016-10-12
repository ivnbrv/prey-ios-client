//
//  Location.swift
//  Prey
//
//  Created by Javier Cala Uribe on 5/05/16.
//  Copyright © 2016 Fork Ltd. All rights reserved.
//

import Foundation

class Ping : PreyAction {
    
    // MARK: Properties
    
    // MARK: Functions    
    
    // Prey command
    func get() {
        
        isActive = true
        PreyLogger("Start ping")

        // Params struct
        let params:[String: String] = [
            kData.status.rawValue   : kStatus.started.rawValue,
            kData.target.rawValue   : kAction.ping.rawValue,
            kData.command.rawValue  : "get"]
        
        self.sendData(params, toEndpoint: responseDeviceEndpoint)
        
        isActive = false
        PreyModule.sharedInstance.checkStatus(self)
    }
}