//
//  LibreFmClient.swift
//  Audioscrobbler
//
//  Created by Audioscrobbler on 24/12/2024.
//

import Foundation

class LibreFmClient: LastFmClient {
    override var baseURL: URL {
        URL(string: "https://libre.fm/2.0/")!
    }
    
    override var authURL: String {
        "https://libre.fm/api/auth/"
    }
}
